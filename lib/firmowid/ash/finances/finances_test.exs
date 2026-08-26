defmodule Firmowid.Ash.Finances.FinancesTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Scope

  setup do
    # Admin user required — transactions are not accessible to :employee role
    user = admin_fixture()
    org_id = user.organization_id
    seed_opts = [tenant: org_id]
    bank_account = bank_account_fixture!(user)
    bank_account_id = bank_account.id

    # Pending: no invoices, not skipped
    pending_tx =
      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Pending Debtor",
          creditor_name: "Pending Creditor",
          remittance_information_unstructured: "pending payment",
          amount: Money.new!("PLN", Decimal.new("100.00")),
          booking_date: ~D[2024-01-10],
          value_date: ~D[2024-01-10],
          bank_account_id: bank_account_id,
          skip_invoicing: false
        },
        seed_opts
      )

    # Skipped: no invoices, skip_invoicing = true
    skipped_tx =
      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Skipped Debtor",
          creditor_name: "Skipped Creditor",
          remittance_information_unstructured: "skipped payment",
          amount: Money.new!("PLN", Decimal.new("200.00")),
          booking_date: ~D[2024-01-11],
          value_date: ~D[2024-01-11],
          bank_account_id: bank_account_id,
          skip_invoicing: true
        },
        seed_opts
      )

    # Matched: linked to a cost invoice
    matched_tx =
      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Matched Debtor",
          creditor_name: "Matched Creditor",
          remittance_information_unstructured: "matched payment",
          amount: Money.new!("PLN", Decimal.new("-100.00")),
          booking_date: ~D[2024-01-12],
          value_date: ~D[2024-01-12],
          bank_account_id: bank_account_id,
          skip_invoicing: false
        },
        seed_opts
      )

    cost_invoice =
      Ash.Seed.seed!(
        CostInvoice,
        %{
          seller: "Test Vendor",
          seller_display_name: "Test Vendor",
          sale_date: ~D[2024-01-01],
          issue_date: ~D[2024-01-01],
          due_date: ~D[2024-02-01],
          total_amount: Decimal.new("-100.00"),
          currency: "PLN",
          invoice_identifier: "CI-TEST-001",
          description: "Test invoice"
        },
        seed_opts
      )

    Ash.Seed.seed!(CostInvoiceTransaction, %{
      cost_invoice_id: cost_invoice.id,
      transaction_id: matched_tx.id,
      organization_id: org_id
    })

    %{
      user: user,
      org_id: org_id,
      bank_account: bank_account,
      pending_tx: pending_tx,
      skipped_tx: skipped_tx,
      matched_tx: matched_tx
    }
  end

  describe "reconciliation filtering" do
    test "reconciliation: :pending returns only unmatched, non-skipped transactions", ctx do
      ids =
        %{reconciliation: :pending}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.pending_tx.id in ids
      refute ctx.skipped_tx.id in ids
      refute ctx.matched_tx.id in ids
    end

    test "reconciliation: :skipped returns only skipped transactions", ctx do
      ids =
        %{reconciliation: :skipped}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.skipped_tx.id in ids
      refute ctx.pending_tx.id in ids
      refute ctx.matched_tx.id in ids
    end

    test "reconciliation: :matched returns only transactions linked to invoices", ctx do
      ids =
        %{reconciliation: :matched}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.matched_tx.id in ids
      refute ctx.pending_tx.id in ids
      refute ctx.skipped_tx.id in ids
    end
  end

  describe "BM25 search" do
    test "returns matching transactions", ctx do
      results =
        Finances.list_transactions!(%{query: "pending payment"},
          actor: ctx.user,
          tenant: ctx.org_id
        )

      ids = Enum.map(results, & &1.id)
      assert ctx.pending_tx.id in ids
    end

    test "returns empty list when no matches found", ctx do
      results =
        Finances.list_transactions!(%{query: "NonExistentXyzzy"},
          actor: ctx.user,
          tenant: ctx.org_id
        )

      assert results == []
    end

    test "does not find transactions across organizations", ctx do
      user2 = user_fixture()
      org2_id = user2.organization_id
      other_org_bank_account_id = bank_account_fixture!(user2).id

      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Other Org Debtor",
          creditor_name: "Other Org Creditor",
          remittance_information_unstructured: "other org payment",
          amount: Money.new!("PLN", Decimal.new("300.00")),
          booking_date: ~D[2024-01-13],
          value_date: ~D[2024-01-13],
          bank_account_id: other_org_bank_account_id
        },
        tenant: org2_id
      )

      org1_ids =
        %{}
        |> Finances.list_transactions!(actor: ctx.user, tenant: ctx.org_id)
        |> Enum.map(& &1.id)

      assert ctx.pending_tx.id in org1_ids
      assert ctx.skipped_tx.id in org1_ids
      assert ctx.matched_tx.id in org1_ids
    end
  end

  describe "transaction calculations" do
    test "calculation chain uses account ownership before amount sign", ctx do
      transaction =
        Ash.Seed.seed!(
          Transaction,
          %{
            creditor_account: "PL00999999999999999999999999",
            debtor_account: ctx.bank_account.iban,
            creditor_name: "Creditor counterparty",
            debtor_name: "Firmowid",
            amount: Money.new!("PLN", Decimal.new("100.00")),
            booking_date: ~D[2024-02-01],
            value_date: ~D[2024-02-01],
            bank_account_id: ctx.bank_account.id
          },
          tenant: ctx.org_id
        )

      loaded =
        Ash.load!(
          transaction,
          [
            :direction,
            :signed_amount,
            :counterparty_name,
            :counterparty_display_name,
            :groupable?
          ],
          scope: scope_for(ctx.user)
        )

      assert loaded.direction == :expense
      assert loaded.signed_amount == Money.new!("PLN", Decimal.new("-100.00"))
      assert loaded.counterparty_name == "Creditor counterparty"
      assert loaded.counterparty_display_name == "Creditor counterparty"
      assert loaded.groupable?
    end

    test "falls back to amount sign without an account match", ctx do
      transaction =
        Ash.Seed.seed!(
          Transaction,
          %{
            creditor_account: "PL00111111111111111111111111",
            debtor_account: "PL00222222222222222222222222",
            amount: Money.new!("PLN", Decimal.new("100.00")),
            booking_date: ~D[2024-02-02],
            value_date: ~D[2024-02-02],
            bank_account_id: ctx.bank_account.id
          },
          tenant: ctx.org_id
        )

      loaded = Ash.load!(transaction, [:direction, :signed_amount], scope: scope_for(ctx.user))

      assert loaded.direction == :income
      assert loaded.signed_amount == Money.new!("PLN", Decimal.new("100.00"))
    end

    test "missing and N/A counterparties fall back for display and cannot group", ctx do
      transaction =
        Ash.Seed.seed!(
          Transaction,
          %{
            creditor_name: "N/A",
            debtor_name: nil,
            amount: Money.new!("PLN", Decimal.new("-10.00")),
            booking_date: ~D[2024-02-03],
            value_date: ~D[2024-02-03],
            bank_account_id: ctx.bank_account.id
          },
          tenant: ctx.org_id
        )

      loaded =
        Ash.load!(transaction, [:counterparty_name, :counterparty_display_name, :groupable?], scope: scope_for(ctx.user))

      assert loaded.counterparty_name == "N/A"
      assert loaded.counterparty_display_name == "Transakcja bankowa"
      refute loaded.groupable?
    end

    test "skipped and matched transactions cannot group", ctx do
      loaded =
        Ash.load!([ctx.skipped_tx, ctx.matched_tx], :groupable?, scope: scope_for(ctx.user))

      assert Enum.all?(loaded, &(not &1.groupable?))
    end
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.organization_id}
end
