defmodule FirmowidWeb.Invoicing.Components.InvoiceDetailsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FirmowidWeb.Invoicing.Components.InvoiceDetails

  test "renders refund label for a positive corrected cost invoice total" do
    html =
      render_component(&InvoiceDetails.invoice_amount/1,
        is_cost_invoice: true,
        total_amount: Money.new!("PLN", "100.00")
      )

    assert html =~ "Razem do zwrotu"
    refute html =~ "Razem do zapłaty"
  end

  test "renders payment label for a cost invoice that is not a refund" do
    html =
      render_component(&InvoiceDetails.invoice_amount/1,
        is_cost_invoice: true,
        total_amount: Money.new!("PLN", "-100.00")
      )

    assert html =~ "Razem do zapłaty"
    refute html =~ "Razem do zwrotu"
  end
end
