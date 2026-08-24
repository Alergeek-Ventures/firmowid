defmodule Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailContentBuilderTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailContentBuilder

  test "builds a Polish sales invoice email in the shared HTML shell" do
    invoice = %{
      buyer_country: "PL",
      invoice_number: "FV/1/2026",
      due_date: ~D[2026-09-01],
      seller_display_name: "Acme <sp. z o.o.>",
      seller_address: "Warszawa"
    }

    share_url = "https://firmowid.example/faktury/FV-1"

    assert {"Faktura FV/1/2026", text, html} =
             SalesInvoiceEmailContentBuilder.build(invoice, :basic, share_url, [])

    assert html =~ "<!doctype html>"
    assert html =~ "alt=\"Firmowid\""
    assert html =~ "Faktura"
    assert html =~ "Acme &lt;sp. z o.o.&gt;"
    assert html =~ "Pozdrawiamy,<br>Zespół Firmowid"
    assert text =~ share_url
  end
end
