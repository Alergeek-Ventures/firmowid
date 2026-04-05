defmodule FirmowidWeb.Invoicing.SalesInvoices.Controllers.Pdf do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.Pdf

  require Logger

  plug :put_view, html: FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  @bridge_opts [authorize?: false, actor: %{}]
  @item_calcs [:net_value, :vat_value, :gross_value]
  @pdf_loads [
    sales_invoice_items: @item_calcs,
    corrections: [sales_invoice_items: @item_calcs],
    reference_invoice: [],
    latest_correction: [sales_invoice_items: @item_calcs]
  ]

  def index(conn, %{"id" => id}) do
    opts = [tenant: conn.assigns.current_user.organization_id, load: @pdf_loads] ++ @bridge_opts

    case SalesInvoice.by_id(id, opts) do
      {:ok, sales_invoice} ->
        logo_url = Invoicing.get_logo_url(sales_invoice.organization_id)
        render_sales_invoice(conn, sales_invoice, logo_url)

      {:error, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp render_sales_invoice(conn, %SalesInvoice{} = sales_invoice, logo_url) do
    alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections

    sales_invoice =
      then(sales_invoice, fn inv -> %{inv | corrections: AnnotatedCorrections.annotate(inv)} end)

    render(conn, :sales_invoice,
      layout: false,
      sales_invoice: sales_invoice,
      currency_rate: Invoicing.get_currency_rate(sales_invoice),
      reference_invoice: sales_invoice.reference_invoice,
      class: "mx-auto",
      show_vat: conn.assigns.current_org.is_vat_payer,
      logo_url: logo_url,
      logo_data_uri: nil,
      footer_logo_data_uri: nil
    )
  end

  def pdf(conn, %{"id" => id}) do
    opts = [tenant: conn.assigns.current_user.organization_id, load: @pdf_loads] ++ @bridge_opts

    case SalesInvoice.by_id(id, opts) do
      {:error, _} ->
        send_resp(conn, 404, "Not found")

      {:ok, sales_invoice} ->
        logo_url = Invoicing.get_logo_url(sales_invoice.organization_id)
        sales_invoice = Map.put(sales_invoice, :logo_url, logo_url)

        case Pdf.generate(sales_invoice, show_vat: conn.assigns.current_org.is_vat_payer) do
          {:ok, pdf_binary} ->
            filename = (sales_invoice.invoice_number || "faktura") <> ".pdf"

            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, pdf_binary)

          {:error, reason} ->
            Logger.error("PDF generation failed for invoice #{id}: #{inspect(reason)}")
            send_resp(conn, 500, "PDF generation failed")
        end
    end
  end
end
