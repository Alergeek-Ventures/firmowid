defmodule Firmowid.Taxes.Forecast.RecalculationTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Finances.BankAccount
  alias Firmowid.Taxes.Forecast.Recalculation
  alias Firmowid.Taxes.TaxYear

  setup do
    user = admin_fixture()
    org_id = user.member.organization_id
    %{worker: worker} = AshOban.Info.oban_scheduled_action(TaxYear, :save_forecasts)

    bank_account =
      Ash.Seed.seed!(
        BankAccount,
        %{
          iban: "PL11111111111111111111111111",
          currency: "PLN",
          name: "Primary account",
          owner_name: "Acme Sp. z o.o.",
          institution_id: "NEST_BANK_CORPORATE_NESBPLPW",
          institution_name: "Test Bank",
          gocardless_id: "gc-account-1"
        },
        tenant: org_id
      )

    {:ok, user: user, org_id: org_id, worker: worker, bank_account: bank_account}
  end

  test "a bank sync queues one delayed recalculation for the organization", ctx do
    today = Date.to_iso8601(Date.utc_today())

    booked =
      for id <- ["payment-1", "payment-2"] do
        %{
          "internalTransactionId" => id,
          "transactionId" => "provider-#{id}",
          "creditorName" => "Example Creditor",
          "creditorAccount" => %{"iban" => "PL002"},
          "transactionAmount" => %{"amount" => "-100.00", "currency" => "PLN"},
          "bookingDate" => today,
          "valueDate" => today,
          "remittanceInformationUnstructured" => "Invoice"
        }
      end

    Req.Test.stub(:bank_data_transactions, fn conn ->
      Req.Test.json(conn, %{transactions: %{booked: booked, pending: []}})
    end)

    opts = [actor: ctx.user, tenant: ctx.org_id, context: %{private: %{ash_oban?: true}}]

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _account} = BankAccount.sync_from_gocardless(ctx.bank_account, opts)

      assert [%{state: "scheduled", args: %{"tenant" => org_id}} = job] =
               all_enqueued(worker: ctx.worker)

      assert org_id == ctx.org_id
      assert DateTime.after?(job.scheduled_at, DateTime.utc_now())
    end)
  end

  test "a burst of changes queues one job while it waits", ctx do
    Oban.Testing.with_testing_mode(:manual, fn ->
      for _change <- 1..3, do: assert(:ok = Recalculation.later(ctx.org_id))

      assert [_one] = all_enqueued(worker: ctx.worker)
    end)
  end
end
