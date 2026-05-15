defmodule FirmowidWeb.Invoicing.Components.EntriesTableTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidWeb.Invoicing.Components.EntriesTable
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  test "draft sales invoice renders szkic label instead of skip button" do
    draft_invoice = %SalesInvoice{
      id: "draft-sales-invoice",
      invoice_number: nil,
      due_date: ~D[2026-04-30],
      issue_date: ~D[2026-04-16],
      sale_date: ~D[2026-04-16],
      gross_value: Decimal.new("100.00"),
      currency: "PLN",
      buyer_display_name_label: "Kontrahent testowy",
      sales_invoice_items: [],
      transactions: [],
      skip_invoicing: false
    }

    html =
      render_component(&EntriesTable.table/1,
        invoicing_entries: [draft_invoice],
        has_connected_bank_account: true,
        mode: :invoices
      )

    assert html =~ "Szkic"
    refute html =~ "toggle-skip-invoicing"
    refute html =~ "Pomiń"
  end

  test "transaction rows preserve return_to navigation context" do
    transaction = %Transaction{
      id: "transaction-row-test",
      creditor_name: "Supplier Sp. z o.o.",
      debtor_name: "Firmowid Sp. z o.o.",
      remittance_information_unstructured: "Payment January",
      transaction_amount: Decimal.new("-100.00"),
      transaction_currency: "PLN",
      booking_date: ~D[2026-01-10],
      value_date: ~D[2026-01-10],
      skip_invoicing: false,
      cost_invoices: [],
      sales_invoices: []
    }

    html =
      render_component(&EntriesTable.table/1,
        invoicing_entries: [transaction],
        has_connected_bank_account: true,
        mode: :transactions,
        return_to: "/fakturowanie?miesiac=2026-01-01&filtr=transakcje"
      )

    assert html =~
             Navigation.transaction_show_path(
               transaction.id,
               "/fakturowanie?miesiac=2026-01-01&filtr=transakcje"
             )
  end
end
