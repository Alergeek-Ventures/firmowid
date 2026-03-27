defmodule Firmowid.BankData.WorkerTest do
  use Firmowid.DataCase

  import Ecto.Query
  import Firmowid.AccountsFixtures

  alias Firmowid.BankData.Requisition
  alias Firmowid.BankData.Worker
  alias Firmowid.Finances
  alias Firmowid.Repo

  @moduletag capture_log: true

  setup do
    :ok
  end

  describe "check_requisition_status" do
    test "processing status returns snooze" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :pending, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      # requisition API returns CR (processing)
      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{status: "CR"})
      end)

      result =
        Worker.perform(%Oban.Job{
          attempt: 1,
          args: %{
            "name" => "check_requisition_status",
            "requisition_id" => req.id,
            "organization_id" => org_id
          }
        })

      assert match?({:snooze, seconds} when is_integer(seconds) and seconds > 0, result)
    end

    test "LN creates bank accounts, enqueues syncs, returns :ok" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :pending, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      # Stubs for LN flow
      Req.Test.stub(:bank_data_requisition, fn conn ->
        path = conn.request_path || ""

        cond do
          String.contains?(path, "/requisitions/") ->
            Req.Test.json(conn, %{id: req.id, status: "LN", accounts: ["acc-1"]})

          String.contains?(path, "/accounts/acc-1/details") ->
            Req.Test.json(conn, %{account: %{name: "Main", iban: "PL00"}})

          true ->
            Req.Test.json(conn, %{})
        end
      end)

      Req.Test.stub(:bank_data_account, fn conn ->
        path = conn.request_path

        if String.contains?(path || "", "/accounts/acc-1") do
          Req.Test.json(conn, %{
            id: "acc-1",
            iban: "PL00",
            institution_id: "N26",
            owner_name: "Owner"
          })
        else
          Req.Test.json(conn, %{})
        end
      end)

      Req.Test.stub(:bank_data_institution, fn conn ->
        Req.Test.json(conn, %{name: "N26"})
      end)

      # transactions stub to satisfy inline sync jobs
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Req.Test.json(conn, %{
          transactions: %{
            booked: [],
            pending: []
          }
        })
      end)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 Worker.perform(%Oban.Job{
                   attempt: 1,
                   args: %{
                     "name" => "check_requisition_status",
                     "requisition_id" => req.id,
                     "organization_id" => org_id
                   }
                 })

        # bank account created
        assert Repo.one(
                 from(b in Finances.BankAccount,
                   where: b.requisition_id == ^req.id,
                   select: count()
                 ),
                 organization_id: org_id
               ) == 1

        # sync jobs enqueued in oban (manual mode records rows)
        count =
          Repo.one(
            from(j in Oban.Job,
              where: fragment("(args->>'name') = ?", "bank_account_sync"),
              select: count()
            ),
            prefix: "oban",
            skip_organization_id: true
          )

        assert count >= 1
      end)
    end

    test "RJ rejects and cancels" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :pending, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{status: "RJ"})
      end)

      assert {:cancel, :rejected} =
               Worker.perform(%Oban.Job{
                 attempt: 1,
                 args: %{
                   "name" => "check_requisition_status",
                   "requisition_id" => req.id,
                   "organization_id" => org_id
                 }
               })

      assert %Requisition{status: :rejected} =
               Repo.get(Requisition, req.id, organization_id: org_id)
    end

    test "EX cancels without db change" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :pending, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{status: "EX"})
      end)

      assert {:cancel, :expired} =
               Worker.perform(%Oban.Job{
                 attempt: 1,
                 args: %{
                   "name" => "check_requisition_status",
                   "requisition_id" => req.id,
                   "organization_id" => org_id
                 }
               })

      assert %Requisition{status: :pending} =
               Repo.get(Requisition, req.id, organization_id: org_id)
    end

    test "timeout after many attempts rejects and cancels" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :pending, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{status: "CR"})
      end)

      assert {:cancel, :timeout} =
               Worker.perform(%Oban.Job{
                 attempt: 25,
                 args: %{
                   "name" => "check_requisition_status",
                   "requisition_id" => req.id,
                   "organization_id" => org_id
                 }
               })

      assert %Requisition{status: :rejected} =
               Repo.get(Requisition, req.id, organization_id: org_id)
    end
  end

  describe "bank_account_sync" do
    test "rate limited snoozes 24h" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :accepted, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      ba =
        Finances.create_bank_account(%{
          iban: "PL123",
          organization_id: org_id,
          requisition_id: req.id,
          gocardless_id: "acc-1"
        })

      # transactions 429
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Plug.Conn.send_resp(conn, 429, "")
      end)

      assert {:snooze, 86_400} =
               Worker.perform(%Oban.Job{
                 args: %{
                   "name" => "bank_account_sync",
                   "bank_account_id" => ba.id,
                   "organization_id" => org_id
                 }
               })
    end

    test "unauthorized returns error (retryable) after refreshing token" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :accepted, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      ba =
        Finances.create_bank_account(%{
          iban: "PL123",
          organization_id: org_id,
          requisition_id: req.id,
          gocardless_id: "acc-1"
        })

      # transactions 401
      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{summary: "Invalid token", detail: "Token is invalid", status_code: 401})
        )
      end)

      assert {:error, :unauthorized} =
               Worker.perform(%Oban.Job{
                 args: %{
                   "name" => "bank_account_sync",
                   "bank_account_id" => ba.id,
                   "organization_id" => org_id
                 }
               })
    end

    test "expired_eua cancels permanently" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :accepted, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      ba =
        Finances.create_bank_account(%{
          iban: "PL123",
          organization_id: org_id,
          requisition_id: req.id,
          gocardless_id: "acc-1"
        })

      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          401,
          Jason.encode!(%{
            summary: "End User Agreement (EUA) abc123 has expired",
            detail: "EUA was valid for 90 days",
            status_code: 401
          })
        )
      end)

      assert {:cancel, :expired_eua} =
               Worker.perform(%Oban.Job{
                 args: %{
                   "name" => "bank_account_sync",
                   "bank_account_id" => ba.id,
                   "organization_id" => org_id
                 }
               })
    end

    test "bad_request cancels permanently" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :accepted, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      ba =
        Finances.create_bank_account(%{
          iban: "PL123",
          organization_id: org_id,
          requisition_id: req.id,
          gocardless_id: "acc-1"
        })

      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{summary: "Bad request", status_code: 400}))
      end)

      assert {:cancel, :bad_request} =
               Worker.perform(%Oban.Job{
                 args: %{
                   "name" => "bank_account_sync",
                   "bank_account_id" => ba.id,
                   "organization_id" => org_id
                 }
               })
    end

    test "conflict returns error (retryable)" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :accepted, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      ba =
        Finances.create_bank_account(%{
          iban: "PL123",
          organization_id: org_id,
          requisition_id: req.id,
          gocardless_id: "acc-1"
        })

      Req.Test.stub(:bank_data_transactions, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          409,
          Jason.encode!(%{summary: "Account suspended", status_code: 409})
        )
      end)

      assert {:error, :conflict} =
               Worker.perform(%Oban.Job{
                 args: %{
                   "name" => "bank_account_sync",
                   "bank_account_id" => ba.id,
                   "organization_id" => org_id
                 }
               })
    end

    test "not_found cancels" do
      assert {:cancel, :not_found} =
               Worker.perform(%Oban.Job{
                 args: %{
                   "name" => "bank_account_sync",
                   "bank_account_id" => UUIDv7.generate(),
                   "organization_id" => UUIDv7.generate()
                 }
               })
    end

    test ":ok on success" do
      %{organization_id: org_id} = admin_fixture()

      {:ok, req} =
        %Requisition{status: :accepted, organization_id: org_id}
        |> Requisition.changeset()
        |> Repo.insert(organization_id: org_id)

      ba =
        Finances.create_bank_account(%{
          iban: "PL123",
          organization_id: org_id,
          requisition_id: req.id,
          gocardless_id: "acc-1"
        })

      # transactions success
      Req.Test.stub(:bank_data_transactions, fn conn ->
        Req.Test.json(conn, %{
          transactions: %{
            booked: [
              %{
                transactionId: "1",
                creditorName: "X",
                creditorAccount: %{iban: "Y"},
                debtorName: "Z",
                debtorAccount: %{iban: "W"},
                transactionAmount: %{currency: "PLN", amount: "-1.00"},
                bookingDate: "2024-01-01",
                valueDate: "2024-01-01",
                remittanceInformationUnstructured: "t"
              }
            ],
            pending: []
          }
        })
      end)

      assert :ok =
               Worker.perform(%Oban.Job{
                 args: %{
                   "name" => "bank_account_sync",
                   "bank_account_id" => ba.id,
                   "organization_id" => org_id
                 }
               })
    end
  end
end
