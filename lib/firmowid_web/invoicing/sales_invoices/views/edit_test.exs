defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.EditTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Invoicing.SalesInvoice

  test "editing foreign invoice does not crash preview money rendering", %{conn: conn} do
    admin = admin_fixture()

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/1",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer,
          invoice_type: :foreign,
          currency: "EUR",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft",
          seller_address: "Address",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Buyer Company",
          buyer_display_name: "Buyer",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("2"),
              unit: "szt",
              unit_price: Decimal.new("10"),
              vat_rate: "np I"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin,
        authorize?: false
      )

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
    assert html =~ "Fakturowanie"
  end
end
