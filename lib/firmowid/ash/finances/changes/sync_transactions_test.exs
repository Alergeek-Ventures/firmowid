defmodule Firmowid.Ash.Finances.Changes.SyncTransactionsTest do
  @moduledoc false
  use Firmowid.DataCase

  import Ash.Expr
  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Events.Event
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Finances.DuplicateTransactionMatcher
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.SystemActor

  require Ash.Query

  setup do
    user = admin_fixture()
    org_id = user.organization_id

    bank_account_1 =
      Ash.Seed.seed!(
        BankAccount,
        %{
          iban: "PL11111111111111111111111111",
          currency: "PLN",
          name: "Primary account",
          owner_name: "Firmowid",
          institution_id: "NEST_BANK_CORPORATE_NESBPLPW",
          institution_name: "Test Bank",
          gocardless_id: "gc-account-1"
        },
        tenant: org_id
      )

    bank_account_2 =
      Ash.Seed.seed!(
        BankAccount,
        %{
          iban: "PL22222222222222222222222222",
          currency: "PLN",
          name: "Secondary account",
          owner_name: "Firmowid",
          institution_id: "OTHER_BANK",
          institution_name: "Test Bank",
          gocardless_id: "gc-account-2"
        },
        tenant: org_id
      )

    actor = %SystemActor{org_id: org_id, role: :bank_sync}

    {:ok, org_id: org_id, user: user, actor: actor, bank_account_1: bank_account_1, bank_account_2: bank_account_2}
  end

  describe "upsert_from_sync identity" do
    test "upserts within the same bank account", ctx do
      attrs = transaction_attrs(ctx.bank_account_1.id, "gc-internal-1")

      assert {:ok, first} =
               Finances.upsert_transaction_from_sync(attrs,
                 actor: ctx.actor,
                 tenant: ctx.org_id
               )

      assert {:ok, second} =
               Finances.upsert_transaction_from_sync(
                 Map.merge(attrs, %{
                   transaction_id: "provider-2",
                   remittance_information_unstructured: "updated remittance"
                 }),
                 actor: ctx.actor,
                 tenant: ctx.org_id
               )

      persisted =
        Transaction
        |> Ash.Query.filter(expr(bank_account_id == ^ctx.bank_account_1.id))
        |> Ash.read!(actor: ctx.actor, tenant: ctx.org_id)

      assert length(persisted) == 1
      assert first.id == second.id
      assert hd(persisted).transaction_id == "provider-2"
      assert hd(persisted).remittance_information_unstructured == "updated remittance"
    end

    test "does not collapse transactions from different bank accounts", ctx do
      attrs = transaction_attrs(ctx.bank_account_1.id, "shared-internal-id")

      assert {:ok, tx_1} =
               Finances.upsert_transaction_from_sync(attrs,
                 actor: ctx.actor,
                 tenant: ctx.org_id
               )

      assert {:ok, tx_2} =
               Finances.upsert_transaction_from_sync(
                 transaction_attrs(ctx.bank_account_2.id, "shared-internal-id"),
                 actor: ctx.actor,
                 tenant: ctx.org_id
               )

      persisted =
        Transaction
        |> Ash.Query.filter(expr(internal_transaction_id == "shared-internal-id"))
        |> Ash.Query.sort(:bank_account_id)
        |> Ash.read!(actor: ctx.actor, tenant: ctx.org_id)

      assert length(persisted) == 2
      assert tx_1.id != tx_2.id

      assert Enum.map(persisted, & &1.bank_account_id) == [
               ctx.bank_account_1.id,
               ctx.bank_account_2.id
             ]
    end
  end

  describe "sync replay window" do
    test "imports full history on first successful sync", ctx do
      old_booking_date = Date.add(Date.utc_today(), -80)

      stub_booked_transactions([
        api_transaction("hist-1", old_booking_date),
        api_transaction("hist-2", Date.utc_today())
      ])

      assert {:ok, _bank_account} =
               ctx.bank_account_1
               |> Ash.Changeset.for_update(:sync_from_gocardless, %{},
                 actor: ctx.user,
                 tenant: ctx.org_id
               )
               |> Ash.update(actor: ctx.user, tenant: ctx.org_id)

      persisted =
        Transaction
        |> Ash.read!(actor: ctx.actor, tenant: ctx.org_id)
        |> Enum.filter(&(&1.bank_account_id == ctx.bank_account_1.id))

      assert Enum.sort(Enum.map(persisted, & &1.internal_transaction_id)) == ["hist-1", "hist-2"]
    end

    test "filters transactions older than dynamic replay cutoff after prior success", ctx do
      last_success_at = DateTime.add(DateTime.utc_now(), -20, :day)
      cutoff_date = Date.add(Date.utc_today(), -27)

      seed_successful_sync_event(ctx.bank_account_1, ctx.org_id, last_success_at)

      stub_booked_transactions([
        api_transaction("kept-window", cutoff_date),
        api_transaction("dropped-old", Date.add(cutoff_date, -1)),
        api_transaction("kept-cutoff", cutoff_date)
      ])

      assert {:ok, _bank_account} =
               ctx.bank_account_1
               |> Ash.Changeset.for_update(:sync_from_gocardless, %{},
                 actor: ctx.user,
                 tenant: ctx.org_id
               )
               |> Ash.update(actor: ctx.user, tenant: ctx.org_id)

      persisted_ids =
        Transaction
        |> Ash.read!(actor: ctx.actor, tenant: ctx.org_id)
        |> Enum.filter(&(&1.bank_account_id == ctx.bank_account_1.id))
        |> Enum.map(& &1.internal_transaction_id)
        |> Enum.sort()

      assert persisted_ids == ["kept-cutoff", "kept-window"]
    end
  end

  describe "fallback dedupe" do
    test "merges changed provider ids when remittance differs by payer prefix and dates align across booking/value pairs",
         ctx do
      previous_sync_at = DateTime.add(DateTime.utc_now(), -10, :day)
      seed_successful_sync_event(ctx.bank_account_1, ctx.org_id, previous_sync_at)

      assert {:ok, existing_transaction} =
               ctx.bank_account_1.id
               |> transaction_attrs("original-internal-id")
               |> Map.merge(%{
                 transaction_id: "original-provider-id",
                 booking_date: ~D[2026-04-20],
                 value_date: ~D[2026-04-20],
                 remittance_information_unstructured: "Usługi informatyczne Faktura 07/02/2026"
               })
               |> Finances.upsert_transaction_from_sync(
                 actor: ctx.actor,
                 tenant: ctx.org_id
               )

      stub_booked_transactions([
        %{
          "internalTransactionId" => "changed-internal-id",
          "transactionId" => "changed-provider-id",
          "debtorName" => "Example Debtor",
          "debtorAccount" => %{"iban" => "PL001"},
          "creditorName" => "Example Creditor",
          "creditorAccount" => %{"iban" => "PL002"},
          "transactionAmount" => %{"amount" => "100.00", "currency" => "PLN"},
          "bookingDate" => "2026-04-21",
          "valueDate" => "2026-04-20",
          "remittanceInformationUnstructured" => "PRZYKŁADOWY NADAWCA, Usługi informatyczne Faktura 07/02/2026"
        }
      ])

      assert {:ok, _bank_account} =
               ctx.bank_account_1
               |> Ash.Changeset.for_update(:sync_from_gocardless, %{},
                 actor: ctx.user,
                 tenant: ctx.org_id
               )
               |> Ash.update(actor: ctx.user, tenant: ctx.org_id)

      persisted =
        Transaction
        |> Ash.read!(actor: ctx.actor, tenant: ctx.org_id)
        |> Enum.filter(&(&1.bank_account_id == ctx.bank_account_1.id))

      assert length(persisted) == 1
      assert hd(persisted).id == existing_transaction.id
      assert hd(persisted).internal_transaction_id == "original-internal-id"
    end

    test "keeps first transaction when multiple incoming rows collapse to the same existing identity",
         ctx do
      previous_sync_at = DateTime.add(DateTime.utc_now(), -10, :day)
      seed_successful_sync_event(ctx.bank_account_1, ctx.org_id, previous_sync_at)

      assert {:ok, existing_transaction} =
               ctx.bank_account_1.id
               |> transaction_attrs("original-internal-id")
               |> Map.merge(%{
                 transaction_id: "original-provider-id",
                 booking_date: ~D[2026-04-20],
                 value_date: ~D[2026-04-20],
                 remittance_information_unstructured: "Usługi informatyczne Faktura 07/02/2026"
               })
               |> Finances.upsert_transaction_from_sync(
                 actor: ctx.actor,
                 tenant: ctx.org_id
               )

      stub_booked_transactions([
        %{
          "internalTransactionId" => "changed-internal-id-1",
          "transactionId" => "changed-provider-id-1",
          "debtorName" => "Example Debtor",
          "debtorAccount" => %{"iban" => "PL001"},
          "creditorName" => "Example Creditor",
          "creditorAccount" => %{"iban" => "PL002"},
          "transactionAmount" => %{"amount" => "100.00", "currency" => "PLN"},
          "bookingDate" => "2026-04-21",
          "valueDate" => "2026-04-20",
          "remittanceInformationUnstructured" => "PRZYKŁADOWY NADAWCA, Usługi informatyczne Faktura 07/02/2026"
        },
        %{
          "internalTransactionId" => "changed-internal-id-2",
          "transactionId" => "changed-provider-id-2",
          "debtorName" => "Example Debtor",
          "debtorAccount" => %{"iban" => "PL001"},
          "creditorName" => "Example Creditor",
          "creditorAccount" => %{"iban" => "PL002"},
          "transactionAmount" => %{"amount" => "100.00", "currency" => "PLN"},
          "bookingDate" => "2026-04-21",
          "valueDate" => "2026-04-20",
          "remittanceInformationUnstructured" => "PRZYKŁADOWY NADAWCA, Usługi informatyczne Faktura 07/02/2026"
        }
      ])

      assert {:ok, _bank_account} =
               ctx.bank_account_1
               |> Ash.Changeset.for_update(:sync_from_gocardless, %{},
                 actor: ctx.user,
                 tenant: ctx.org_id
               )
               |> Ash.update(actor: ctx.user, tenant: ctx.org_id)

      persisted =
        Transaction
        |> Ash.read!(actor: ctx.actor, tenant: ctx.org_id)
        |> Enum.filter(&(&1.bank_account_id == ctx.bank_account_1.id))

      assert length(persisted) == 1
      assert hd(persisted).id == existing_transaction.id
      assert hd(persisted).internal_transaction_id == "original-internal-id"
      assert hd(persisted).transaction_id == "original-provider-id"
    end

    test "prefers the exact-date duplicate candidate when repeated transactions create ambiguous matches" do
      older_transaction = %{
        booking_date: ~D[2026-04-22],
        value_date: ~D[2026-04-22],
        internal_transaction_id: "older-internal-id",
        transaction_amount: Decimal.new("-35.56"),
        transaction_currency: "EUR",
        debtor_name: "N/A",
        debtor_account: "N/A",
        creditor_name: "Liam Brown",
        creditor_account: "GB49BARC20040478743951",
        remittance_information_unstructured: "Water invoice #5678"
      }

      exact_date_transaction = %{
        booking_date: ~D[2026-04-23],
        value_date: ~D[2026-04-23],
        internal_transaction_id: "exact-date-internal-id",
        transaction_amount: Decimal.new("-35.56"),
        transaction_currency: "EUR",
        debtor_name: "N/A",
        debtor_account: "N/A",
        creditor_name: "Liam Brown",
        creditor_account: "GB49BARC20040478743951",
        remittance_information_unstructured: "Water invoice #5678"
      }

      incoming_transaction = %{
        booking_date: "2026-04-23",
        value_date: "2026-04-23",
        internal_transaction_id: "changed-internal-id",
        transaction_amount: "-35.56",
        transaction_currency: "EUR",
        debtor_name: "N/A",
        debtor_account: "N/A",
        creditor_name: "Liam Brown",
        creditor_account: "GB49BARC20040478743951",
        remittance_information_unstructured: "Water invoice #5678"
      }

      assert DuplicateTransactionMatcher.unique_match(
               incoming_transaction,
               [older_transaction, exact_date_transaction]
             ) == exact_date_transaction
    end
  end

  defp transaction_attrs(bank_account_id, internal_transaction_id) do
    %{
      bank_account_id: bank_account_id,
      internal_transaction_id: internal_transaction_id,
      transaction_id: "provider-1",
      debtor_name: "Example Debtor",
      debtor_account: "PL001",
      creditor_name: "Example Creditor",
      creditor_account: "PL002",
      transaction_amount: Decimal.new("100.00"),
      transaction_currency: "PLN",
      booking_date: ~D[2026-04-23],
      value_date: ~D[2026-04-23],
      remittance_information_unstructured: "initial remittance"
    }
  end

  defp api_transaction(internal_transaction_id, booking_date, value_date \\ :same_as_booking) do
    value_date = if value_date == :same_as_booking, do: booking_date, else: value_date

    %{
      "internalTransactionId" => internal_transaction_id,
      "transactionId" => "provider-#{internal_transaction_id}",
      "debtorName" => "Example Debtor",
      "debtorAccount" => %{"iban" => "PL001"},
      "creditorName" => "Example Creditor",
      "creditorAccount" => %{"iban" => "PL002"},
      "transactionAmount" => %{"amount" => "100.00", "currency" => "PLN"},
      "bookingDate" => booking_date && Date.to_iso8601(booking_date),
      "valueDate" => value_date && Date.to_iso8601(value_date),
      "remittanceInformationUnstructured" => "initial remittance"
    }
  end

  defp stub_booked_transactions(booked_transactions) do
    Req.Test.stub(:bank_data_transactions, fn conn ->
      Req.Test.json(conn, %{
        transactions: %{
          booked: booked_transactions,
          pending: []
        }
      })
    end)
  end

  defp seed_successful_sync_event(bank_account, org_id, occurred_at) do
    Ash.Seed.seed!(
      Event,
      %{
        organization_id: org_id,
        record_id: bank_account.id,
        resource: BankAccount,
        action: :sync_from_gocardless,
        action_type: :update,
        occurred_at: occurred_at,
        metadata: %{},
        data: %{},
        changed_attributes: %{},
        version: 1
      },
      tenant: org_id
    )
  end
end
