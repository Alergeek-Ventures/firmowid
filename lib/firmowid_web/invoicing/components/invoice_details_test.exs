defmodule FirmowidWeb.Invoicing.Components.InvoiceDetailsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FirmowidWeb.Invoicing.Components.InvoiceDetails

  test "renders refund label for a positive corrected cost invoice total" do
    html =
      render_component(&InvoiceDetails.invoice_amount/1,
        is_cost_invoice: true,
        amount: Money.new!("PLN", "100.00")
      )

    assert html =~ "Razem do zwrotu"
    refute html =~ "Razem do zapłaty"
  end

  test "renders payment label for a cost invoice that is not a refund" do
    html =
      render_component(&InvoiceDetails.invoice_amount/1,
        is_cost_invoice: true,
        amount: Money.new!("PLN", "-100.00")
      )

    assert html =~ "Razem do zapłaty"
    refute html =~ "Razem do zwrotu"
  end

  test "renders payment label for a buyer-facing invoice with a positive total" do
    html =
      render_component(&InvoiceDetails.invoice_amount/1,
        is_cost_invoice: false,
        amount: Money.new!("PLN", "100.00")
      )

    assert html =~ "Razem do zapłaty"
    refute html =~ "Razem do zwrotu"
  end

  test "shared candidate rows preserve the invoice confirmation target and confidence indicator" do
    transaction = %{
      id: "invoice-candidate",
      creditor_name: "Example supplier",
      remittance_information_unstructured: "Payment for invoice FV/2026/10",
      booking_date: ~D[2026-10-11],
      amount: Money.new!(:PLN, -100)
    }

    html =
      render_component(&InvoiceDetails.potential_transactions_list/1,
        potential_transactions: [{transaction, 0.95}],
        name_field: :creditor_name
      )

    assert html =~ "Example supplier"
    assert html =~ ~s(id="potential-transaction-invoice-candidate")
    assert html =~ ~s(phx-click="connect")
    assert html =~ ~s(phx-value-transaction_id="invoice-candidate")
    assert html =~ ~s(id="match-prediction-score-invoice-candidate")
  end
end
