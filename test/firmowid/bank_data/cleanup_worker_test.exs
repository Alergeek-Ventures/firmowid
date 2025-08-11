defmodule Firmowid.BankData.CleanupWorkerTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.BankData.CleanupWorker
  alias Firmowid.BankData.Requisition
  alias Firmowid.Finances.BankAccount
  alias Firmowid.Repo

  @moduletag capture_log: true

  setup do
    # Stub GoCardless requisition GET/DELETE and agreement DELETE endpoints
    Req.Test.stub(:bank_data_requisition, fn conn ->
      path = conn.request_path || ""

      cond do
        conn.method == "GET" and String.contains?(path, "/requisitions/") ->
          Req.Test.json(conn, %{"agreement" => "agreement-123"})

        conn.method == "DELETE" and String.contains?(path, "/requisitions/") ->
          Plug.Conn.send_resp(conn, 204, "")

        conn.method == "DELETE" and String.contains?(path, "/agreements/") ->
          Plug.Conn.send_resp(conn, 204, "")

        true ->
          # Fallback OK
          Plug.Conn.send_resp(conn, 200, "{}")
      end
    end)

    :ok
  end

  test "stale pending (>1h) are rejected and deleted (orphaned)" do
    %{organization_id: org_id} = admin_fixture()

    {:ok, req} =
      %Requisition{status: :pending, organization_id: org_id}
      |> Requisition.changeset()
      |> Repo.insert(organization_id: org_id)

    # backdate inserted_at by 2 hours
    two_hours_ago = DateTime.add(DateTime.utc_now(), -7200, :second)

    Repo.update_all(
      from(r in Requisition, where: r.id == ^req.id),
      [set: [inserted_at: two_hours_ago]],
      organization_id: org_id
    )

    assert :ok == CleanupWorker.perform(%Oban.Job{args: %{}})

    refute Repo.get(Requisition, req.id, organization_id: org_id)
  end

  test "expired (90+ days) remote deletion keeps local row when accounts exist" do
    %{organization_id: org_id} = admin_fixture()

    {:ok, req} =
      %Requisition{status: :accepted, organization_id: org_id}
      |> Requisition.changeset()
      |> Repo.insert(organization_id: org_id)

    # create associated bank account
    %BankAccount{iban: "PL123", organization_id: org_id, requisition_id: req.id}
    |> BankAccount.changeset()
    |> Repo.insert!(organization_id: org_id)

    # backdate inserted_at by 100 days
    long_ago = DateTime.add(DateTime.utc_now(), -100, :day)

    Repo.update_all(
      from(r in Requisition, where: r.id == ^req.id),
      [set: [inserted_at: long_ago]],
      organization_id: org_id
    )

    assert :ok == CleanupWorker.perform(%Oban.Job{args: %{}})

    # requisition still exists
    assert Repo.get(Requisition, req.id, organization_id: org_id)

    # bank account still exists
    assert Repo.one(
             from(b in BankAccount, where: b.requisition_id == ^req.id, select: count()),
             organization_id: org_id
           ) == 1
  end
end
