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
        actor: admin
      )

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
    assert html =~ "Fakturowanie"
  end

  test "payment suggestions set due date from invoice issue date in edit", %{conn: conn} do
    admin = admin_fixture()

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/2",
          issue_date: ~D[2026-01-10],
          sale_date: ~D[2026-01-10],
          due_date: ~D[2026-01-24],
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
        actor: admin
      )

    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")

    view
    |> element("button[phx-click='suggest_payment_date'][phx-value-field='due_date'][phx-value-suggestion='days_7']")
    |> render_click()

    assert render(view) =~ ~s(value="2026-01-17")
  end

  test "confirmed invoice opens the edit form unless it is locked", %{conn: conn} do
    admin = admin_fixture()

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/TEST/3",
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
        actor: admin
      )

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
    assert html =~ "Edycja faktury"

    Ash.Seed.update!(invoice, %{locked_at: DateTime.utc_now()})
    show_path = "/sprzedazowe/#{invoice.id}"

    assert {:error,
            {:live_redirect,
             %{
               to: ^show_path,
               flash: %{
                 "error" => "Nie można edytować tej faktury — jest zablokowana podczas wysyłki do KSeF."
               }
             }}} = live(conn, ~p"/sprzedazowe/#{invoice.id}/edytuj")
  end
end
