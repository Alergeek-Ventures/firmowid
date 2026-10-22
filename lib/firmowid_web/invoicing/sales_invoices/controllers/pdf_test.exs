defmodule FirmowidWeb.Invoicing.SalesInvoices.Controllers.PdfTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Scope
  alias Firmowid.InvoicingFixtures

  test "renders a correction preview with its reference invoice amount", %{conn: conn} do
    admin = admin_fixture()
    scope = %Scope{actor: admin, tenant: admin.member.organization_id}
    original = sales_invoice_fixture!(admin)

    correction =
      original
      |> Map.take([:sale_date, :due_date, :payment_method, :seller_account_number, :invoice_type])
      |> Map.merge(%{
        invoice_number: "FK/#{System.unique_integer([:positive])}",
        issue_date: ~D[2026-01-11],
        ksef_invoice_kind: :kor,
        corrected_invoice_id: original.id,
        correction_reason: "Corrected line",
        currency: "EUR",
        seller_nip: original.seller_nip,
        seller_display_name: original.seller_display_name,
        seller_address: original.seller_address,
        buyer_type: :company,
        buyer_id: original.buyer_id,
        buyer_full_name: original.buyer_full_name,
        buyer_address: original.buyer_address,
        buyer_country: original.buyer_country,
        sales_invoice_items: [
          %{
            name: "Corrected line",
            quantity: Decimal.new("1"),
            unit: "szt",
            unit_price: Decimal.new("50"),
            vat_rate: "23"
          }
        ]
      })
      |> InvoicingFixtures.seed_sales_invoice!(scope: scope)

    conn = conn |> log_in_user(admin) |> get(~p"/sprzedazowe/#{correction.id}/pdf")

    assert html_response(conn, 200) =~ "Razem do zapłaty / Total:"
  end

  defp sales_invoice_fixture!(admin) do
    {:ok, invoice} =
      InvoicingFixtures.seed_sales_invoice(
        %{
          invoice_number: "FV/PDF/#{System.unique_integer([:positive])}",
          issue_date: ~D[2026-01-10],
          sale_date: ~D[2026-01-10],
          due_date: ~D[2026-01-24],
          payment_method: :transfer,
          seller_account_number: "PL61109010140000071219812874",
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
        tenant: admin.member.organization_id,
        actor: admin
      )

    invoice
  end
end
