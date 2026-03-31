defmodule FirmowidWeb.Invoicing.SalesInvoices.Controllers.Pdf do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.Pdf

  require Logger

  plug :put_view, html: FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  @bridge_opts [authorize?: false, actor: %{}]

  def index(conn, %{"id" => id}) do
    opts = [tenant: conn.assigns.current_user.organization_id] ++ @bridge_opts

    case AshSalesInvoice.by_id(id, opts) do
      {:ok, sales_invoice} ->
        sales_invoice = AshSalesInvoice.populate_logo_url(sales_invoice)
        Bodyguard.permit!(SalesInvoices, :show, conn.assigns.current_user, sales_invoice)
        render_sales_invoice(conn, sales_invoice)

      {:error, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp render_sales_invoice(conn, %AshSalesInvoice{} = sales_invoice) do
    sales_invoice = AshSalesInvoice.populate_reference_invoices(sales_invoice)

    render(conn, :sales_invoice,
      layout: false,
      sales_invoice: sales_invoice,
      currency_rate: AshSalesInvoice.get_currency_rate(sales_invoice),
      reference_invoice: sales_invoice.reference_invoice,
      class: "mx-auto",
      show_vat: conn.assigns.current_org.is_vat_payer,
      logo_data_uri: nil,
      footer_logo_data_uri: nil
    )
  end

  def pdf(conn, %{"id" => id}) do
    opts = [tenant: conn.assigns.current_user.organization_id] ++ @bridge_opts

    case AshSalesInvoice.by_id(id, opts) do
      {:error, _} ->
        send_resp(conn, 404, "Not found")

      {:ok, sales_invoice} ->
        sales_invoice = AshSalesInvoice.populate_logo_url(sales_invoice)
        Bodyguard.permit!(SalesInvoices, :show, conn.assigns.current_user, sales_invoice)

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
