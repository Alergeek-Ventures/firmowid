defmodule Firmowid.Finances.RequisitionTest do
  @moduledoc false
  use Firmowid.DataCase

  import ExUnit.CaptureLog
  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Finances.Requisition
  alias Firmowid.SystemActor

  describe "check_status" do
    test "transitions to rejected when GoCardless returns not_found" do
      user = admin_fixture()

      Req.Test.stub(:bank_data_requisition, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      {:ok, requisition} =
        create_requisition(user)

      assert {:ok, _} =
               requisition
               |> Ash.Changeset.for_update(:check_status, %{}, ash_oban_opts(user))
               |> Ash.update(ash_oban_opts(user))

      assert {:ok, refreshed} =
               Firmowid.Finances.get_requisition(requisition.id,
                 tenant: user.member.organization_id,
                 actor: user
               )

      assert refreshed.status == :rejected
    end

    test "keeps the requisition pending when GoCardless fails to list its accounts" do
      user = admin_fixture()

      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{"status" => "LN", "accounts" => ["account-1"]})
      end)

      Req.Test.stub(:bank_data_account, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      {:ok, requisition} = create_requisition(user)

      capture_log(fn ->
        assert {:error, _} =
                 requisition
                 |> Ash.Changeset.for_update(:check_status, %{}, ash_oban_opts(user))
                 |> Ash.update(ash_oban_opts(user))
      end)

      assert {:ok, refreshed} =
               Firmowid.Finances.get_requisition(requisition.id,
                 tenant: user.member.organization_id,
                 actor: user,
                 load: [:bank_accounts]
               )

      assert refreshed.status == :pending
      assert refreshed.bank_accounts == []
    end
  end

  describe "auto_reject" do
    test "uses a valid state-machine transition from pending" do
      user = admin_fixture()

      {:ok, requisition} =
        create_requisition(user)

      assert {:ok, rejected} =
               requisition
               |> Ash.Changeset.for_update(:auto_reject, %{}, ash_oban_opts(user))
               |> Ash.update(ash_oban_opts(user))

      assert rejected.status == :rejected
    end
  end

  describe "expire" do
    test "allows the bank sync system actor to expire an accepted requisition" do
      user = admin_fixture()
      actor = %SystemActor{org_id: user.member.organization_id, role: :bank_sync}

      requisition =
        Ash.Seed.seed!(
          Requisition,
          %{
            id: Ecto.UUID.generate(),
            status: :accepted
          },
          tenant: user.member.organization_id
        )

      assert {:ok, expired} =
               Requisition.expire(requisition,
                 actor: actor,
                 tenant: user.member.organization_id
               )

      assert expired.status == :expired
    end
  end

  describe "organization admin" do
    test "cannot read other organizations' requisitions or run internal actions" do
      admin = admin_fixture()
      other_organization_id = admin_fixture().member.organization_id
      opts = [actor: admin, tenant: admin.member.organization_id]

      Ash.Seed.seed!(Requisition, %{id: Ecto.UUID.generate()}, tenant: other_organization_id)
      {:ok, requisition} = create_requisition(admin)

      assert {:ok, %{results: []}} = Requisition.read_global(actor: admin, page: [limit: 10])
      assert {:error, %Forbidden{}} = Requisition.persist(%{id: Ecto.UUID.generate()}, opts)
      assert {:error, %Forbidden{}} = Requisition.accept(requisition, opts)
      assert {:error, %Forbidden{}} = Requisition.destroy(requisition, opts)
    end
  end

  describe "AshOban queue routing" do
    test "routes requisition triggers to requisition_checks queue" do
      assert :requisition_checks ==
               AshOban.Info.oban_trigger(Requisition, :check_status).queue

      assert :requisition_checks ==
               AshOban.Info.oban_trigger(Requisition, :auto_reject).queue

      assert :requisition_checks ==
               AshOban.Info.oban_trigger(Requisition, :cleanup_orphan).queue

      assert :requisition_checks ==
               AshOban.Info.oban_trigger(Requisition, :delete_remote).queue
    end
  end

  # The options AshOban runs trigger actions with.
  defp ash_oban_opts(user) do
    [actor: user, tenant: user.member.organization_id, context: %{private: %{ash_oban?: true}}]
  end

  defp create_requisition(user) do
    %{id: Ecto.UUID.generate()}
    |> Requisition.changeset_to_persist(
      tenant: user.member.organization_id,
      actor: user,
      authorize?: false
    )
    |> Ash.create(tenant: user.member.organization_id, actor: user, authorize?: false)
  end
end
