defmodule FirmowidWeb.Invoicing.Components.EntriesTableTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidWeb.Invoicing.Components.EntriesTable

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
end
