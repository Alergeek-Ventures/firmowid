defmodule Firmowid.Ash.Analysis.AnalysisTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  describe "own-account transfers" do
    test "excludes internal transfers while retaining invoices with external matches" do
      user = admin_fixture()
      organization_id = user.organization_id
      scope = %Scope{actor: user, tenant: organization_id}
      source_account = bank_account_fixture!(user)
      destination_account = bank_account_fixture!(user)

      internal_incoming =
        transaction!(organization_id, source_account.id, %{
          amount: Money.new!("PLN", Decimal.new("100.00")),
          debtor_account: format_iban(destination_account.iban),
          booking_date: ~D[2024-04-10],
          value_date: ~D[2024-04-10]
        })

      internal_outgoing =
        transaction!(organization_id, source_account.id, %{
          amount: Money.new!("PLN", Decimal.new("-100.00")),
          creditor_account: destination_account.iban,
          booking_date: ~D[2024-04-11],
          value_date: ~D[2024-04-11]
        })

      external_incoming =
        transaction!(organization_id, source_account.id, %{
          amount: Money.new!("PLN", Decimal.new("200.00")),
          debtor_account: "PL00123456789012345678901234",
          booking_date: ~D[2024-05-10],
          value_date: ~D[2024-05-10]
        })

      external_outgoing =
        transaction!(organization_id, source_account.id, %{
          amount: Money.new!("PLN", Decimal.new("-200.00")),
          creditor_account: "PL00987654321098765432109876",
          booking_date: ~D[2024-05-11],
          value_date: ~D[2024-05-11]
        })

      internal_sales_invoice = sales_invoice!(organization_id, "INTERNAL-SALES", ~D[2024-04-10])
      external_sales_invoice = sales_invoice!(organization_id, "EXTERNAL-SALES", ~D[2024-05-10])
      mixed_sales_invoice = sales_invoice!(organization_id, "MIXED-SALES", ~D[2024-05-10])
      internal_cost_invoice = cost_invoice!(organization_id, "INTERNAL-COST", ~D[2024-04-11])
      external_cost_invoice = cost_invoice!(organization_id, "EXTERNAL-COST", ~D[2024-05-11])

      link_sales_invoice!(internal_sales_invoice, internal_incoming, organization_id)
      link_sales_invoice!(external_sales_invoice, external_incoming, organization_id)
      link_sales_invoice!(mixed_sales_invoice, internal_incoming, organization_id)
      link_sales_invoice!(mixed_sales_invoice, external_incoming, organization_id)
      link_cost_invoice!(internal_cost_invoice, internal_outgoing, organization_id)
      link_cost_invoice!(external_cost_invoice, external_outgoing, organization_id)

      analysis_scope =
        %Scope{
          actor: %SystemActor{org_id: organization_id, role: :analysis_reader},
          tenant: organization_id
        }

      assert [external_incoming.id] ==
               external_sales_invoice
               |> Ash.load!(:transactions, scope: analysis_scope)
               |> Map.fetch!(:transactions)
               |> Enum.map(& &1.id)

      internal_skipped =
        transaction!(organization_id, source_account.id, %{
          amount: Money.new!("PLN", Decimal.new("100.00")),
          debtor_account: destination_account.iban,
          booking_date: ~D[2024-04-12],
          value_date: ~D[2024-04-12],
          skip_invoicing: true
        })

      external_skipped =
        transaction!(organization_id, source_account.id, %{
          amount: Money.new!("PLN", Decimal.new("100.00")),
          debtor_account: "PL00555555555555555555555555",
          booking_date: ~D[2024-05-12],
          value_date: ~D[2024-05-12],
          skip_invoicing: true
        })

      april = Analysis.get_organization_totals(~D[2024-04-01], ~D[2024-04-30], [], scope)
      may = Analysis.get_organization_totals(~D[2024-05-01], ~D[2024-05-31], [], scope)
      months = Analysis.get_months_with_entries(scope)

      assert april.sales_invoices == []
      assert april.cost_invoices == []
      assert april.transactions == []

      assert MapSet.new(Enum.map(may.sales_invoices, & &1.id)) ==
               MapSet.new([external_sales_invoice.id, mixed_sales_invoice.id])

      assert Enum.map(may.cost_invoices, & &1.id) == [external_cost_invoice.id]
      assert Enum.map(may.transactions, & &1.id) == [external_skipped.id]
      refute Date.beginning_of_month(internal_skipped.booking_date) in months
      assert Date.beginning_of_month(external_skipped.booking_date) in months
    end
  end

  defp transaction!(organization_id, bank_account_id, attrs) do
    unique = System.unique_integer([:positive])

    Ash.Seed.seed!(
      Transaction,
      Map.merge(
        %{
          transaction_id: "TX-ANALYSIS-#{unique}",
          internal_transaction_id: "INT-ANALYSIS-#{unique}",
          debtor_name: "Debtor",
          debtor_account: "N/A",
          creditor_name: "Creditor",
          creditor_account: "N/A",
          amount: Money.new!("PLN", Decimal.new("100.00")),
          booking_date: ~D[2024-05-01],
          value_date: ~D[2024-05-01],
          bank_account_id: bank_account_id,
          organization_id: organization_id,
          skip_invoicing: false
        },
        attrs
      )
    )
  end

  defp sales_invoice!(organization_id, invoice_number, sale_date) do
    Ash.Seed.seed!(SalesInvoice, %{
      invoice_number: invoice_number,
      buyer_full_name: "Buyer",
      seller_display_name: "Our Company",
      sale_date: sale_date,
      issue_date: sale_date,
      due_date: sale_date,
      payment_method: :transfer,
      currency: "PLN",
      buyer_type: :company,
      organization_id: organization_id
    })
  end

  defp cost_invoice!(organization_id, identifier, sale_date) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: "Seller",
      seller_display_name: "Seller",
      invoice_identifier: identifier,
      description: "Cost invoice",
      sale_date: sale_date,
      issue_date: sale_date,
      due_date: sale_date,
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      organization_id: organization_id
    })
  end

  defp link_sales_invoice!(invoice, transaction, organization_id) do
    Ash.Seed.seed!(SalesInvoiceTransaction, %{
      sales_invoice_id: invoice.id,
      transaction_id: transaction.id,
      organization_id: organization_id
    })
  end

  defp link_cost_invoice!(invoice, transaction, organization_id) do
    Ash.Seed.seed!(CostInvoiceTransaction, %{
      cost_invoice_id: invoice.id,
      transaction_id: transaction.id,
      organization_id: organization_id
    })
  end

  defp format_iban(<<country::binary-size(2), rest::binary>>), do: country <> " " <> rest
end
