defmodule Firmowid.Ash.Finances.RequisitionTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Finances.Requisition

  describe "check_status" do
    test "transitions to rejected when GoCardless returns not_found" do
      user = admin_fixture()

      Req.Test.stub(:bank_data_requisition, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      {:ok, requisition} =
        Requisition
        |> Ash.Changeset.for_create(:persist, %{id: Ecto.UUID.generate()},
          tenant: user.organization_id,
          actor: user,
          authorize?: false
        )
        |> Ash.create(tenant: user.organization_id, actor: user, authorize?: false)

      assert {:ok, _} =
               requisition
               |> Ash.Changeset.for_update(:check_status, %{},
                 tenant: user.organization_id,
                 actor: user,
                 authorize?: false
               )
               |> Ash.update(tenant: user.organization_id, actor: user, authorize?: false)

      assert {:ok, refreshed} =
               Ash.get(Requisition, requisition.id,
                 tenant: user.organization_id,
                 actor: user,
                 authorize?: false
               )

      assert refreshed.status == :rejected
    end
  end

  describe "auto_reject" do
    test "uses a valid state-machine transition from pending" do
      user = admin_fixture()

      {:ok, requisition} =
        Requisition
        |> Ash.Changeset.for_create(:persist, %{id: Ecto.UUID.generate()},
          tenant: user.organization_id,
          actor: user,
          authorize?: false
        )
        |> Ash.create(tenant: user.organization_id, actor: user, authorize?: false)

      assert {:ok, rejected} =
               requisition
               |> Ash.Changeset.for_update(:auto_reject, %{},
                 tenant: user.organization_id,
                 actor: user,
                 authorize?: false
               )
               |> Ash.update(tenant: user.organization_id, actor: user, authorize?: false)

      assert rejected.status == :rejected
    end
  end
end
