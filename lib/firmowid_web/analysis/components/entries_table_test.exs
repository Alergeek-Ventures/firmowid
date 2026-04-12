defmodule FirmowidWeb.Analysis.Components.EntriesTableTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Transaction
  alias FirmowidWeb.Analysis.Components.EntriesTable

  test "renders fallback amount when transaction money cannot be built" do
    transaction =
      Map.put(
        %Transaction{
          id: "tx-fallback",
          transaction_amount: Decimal.new("12.34"),
          transaction_currency: "BAD",
          debtor_name: "Debtor",
          creditor_name: "Creditor",
          remittance_information_unstructured: "Fallback transaction",
          booking_date: ~D[2026-04-12],
          skip_invoicing: true
        },
        :entity_tags,
        []
      )

    html =
      render_component(&EntriesTable.table/1,
        entries: [transaction],
        tag_definitions: []
      )

    assert html =~ "Fallback transaction"
    assert html =~ "—"
  end
end
