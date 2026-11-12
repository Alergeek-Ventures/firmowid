defmodule Firmowid.Invoicing.Services.SalesInvoiceEmailContentBuilderTest do
  use ExUnit.Case, async: true

  alias Firmowid.Invoicing.Services.SalesInvoiceEmailContentBuilder

  test "builds a Polish sales invoice email with the amount and transfer details" do
    invoice = %{
      buyer_country: "PL",
      buyer_display_name: "Lumen Studio",
      invoice_number: "FV/1/2026",
      due_date: ~D[2026-09-01],
      seller_display_name: "Acme <sp. z o.o.>",
      amount: Money.new(:PLN, "12300.00"),
      ksef_invoice_kind: :vat,
      is_paid_on_issue: false,
      is_correction: false,
      payment_method: :transfer,
      seller_account_number: "61 1090 1014 0000 0712 1981 2874"
    }

    share_url = "https://firmowid.example/faktury/FV-1"

    assert {"Faktura FV/1/2026", text, html} =
             SalesInvoiceEmailContentBuilder.build(invoice, :basic, share_url, [])

    assert html =~ "<!doctype html>"
    assert html =~ "Faktura od Acme &lt;sp. z o.o.&gt;"
    assert html =~ "01.09.2026"
    assert html =~ "61 1090 1014 0000 0712 1981 2874"
    assert text =~ "12\u00A0300,00\u00A0zł"
    assert text =~ share_url
  end
end
