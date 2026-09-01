defmodule FirmowidWeb.Invoicing.SalesInvoices.Controllers.PdfTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope

  test "renders a correction preview with its reference invoice amount", %{conn: conn} do
    admin = admin_fixture()
    scope = %Scope{actor: admin, tenant: admin.organization_id}
    original = sales_invoice_fixture!(admin)

    {:ok, correction} =
      SalesInvoice.create_correction(
        %{
          original_invoice_id: original.id,
          invoice_number: "FK/#{System.unique_integer([:positive])}",
          issue_date: ~D[2026-01-11],
          currency: "EUR",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Corrected line",
              quantity: Decimal.new("1"),
              unit: "szt",
              unit_price: Decimal.new("50"),
              vat_rate: "23"
            }
          ]
        },
        scope: scope
      )

    conn = conn |> log_in_user(admin) |> get(~p"/sprzedazowe/#{correction.id}/pdf")

    assert html_response(conn, 200) =~ "Razem do zapłaty / Total:"
  end

  defp sales_invoice_fixture!(admin) do
    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_number: "FV/PDF/#{System.unique_integer([:positive])}",
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
          buyer_full_name: "Acme Corp",
          buyer_display_name: "Acme Corp",
          buyer_address: "Buyer address",
          buyer_country: "PL",
          sales_invoice_items: [
            %{
              index: 0,
              name: "Line",
              quantity: Decimal.new("1"),
              unit: "szt",
              unit_price: Decimal.new("100"),
              vat_rate: "23"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin
      )

    invoice
  end
end
