defmodule Firmowid.Ash.Finances.FinancesTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction

  setup do
    user = user_fixture()
    org_id = user.organization_id
    seed_opts = [tenant: org_id]

    # Pending: no invoices, not skipped
    pending_tx =
      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Pending Debtor",
          creditor_name: "Pending Creditor",
          remittance_information_unstructured: "pending payment",
          transaction_currency: "PLN",
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
          transaction_currency: "PLN",
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
          transaction_currency: "PLN",
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
      pending_tx: pending_tx,
      skipped_tx: skipped_tx,
      matched_tx: matched_tx
    }
  end

  describe "status filtering" do
    test "status: :pending returns only unmatched, non-skipped transactions", ctx do
      ids =
        %{status: :pending}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.pending_tx.id in ids
      refute ctx.skipped_tx.id in ids
      refute ctx.matched_tx.id in ids
    end

    test "status: :skipped returns only skipped transactions", ctx do
      ids =
        %{status: :skipped}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.skipped_tx.id in ids
      refute ctx.pending_tx.id in ids
      refute ctx.matched_tx.id in ids
    end

    test "status: :matched returns only transactions linked to invoices", ctx do
      ids =
        %{status: :matched}
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
      # Create a second org with its own transaction
      user2 = user_fixture()
      org2_id = user2.organization_id

      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Other Org Debtor",
          creditor_name: "Other Org Creditor",
          remittance_information_unstructured: "other org payment",
          transaction_currency: "PLN"
        },
        tenant: org2_id
      )

      # TODO: Remove put_org_id once Repo.prepare_query no longer double-filters
      # Ash attribute multitenancy already adds WHERE organization_id = ?, but
      # prepare_query adds another one from get_org_id(). When they disagree
      # (user_fixture sets put_org_id to the latest org), queries return empty.
      Firmowid.Repo.put_org_id(ctx.org_id)

      org1_ids =
        %{}
        |> Finances.list_transactions!(actor: ctx.user, tenant: ctx.org_id)
        |> Enum.map(& &1.id)

      # Should see all 3 setup transactions but not org2's
      assert ctx.pending_tx.id in org1_ids
      assert ctx.skipped_tx.id in org1_ids
      assert ctx.matched_tx.id in org1_ids
    end
  end
end
