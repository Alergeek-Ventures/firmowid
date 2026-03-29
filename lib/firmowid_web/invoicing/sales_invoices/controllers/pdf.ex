defmodule FirmowidWeb.Invoicing.SalesInvoices.Controllers.Pdf do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.Pdf

  require Logger

  plug :put_view, html: FirmowidWeb.Invoicing.SalesInvoices.Components.Pdf

  def index(conn, %{"id" => id}) do
    sales_invoice =
      SalesInvoices.get_sales_invoice_with_logo_url(id)

    # Authorization check - prevent cross-organization access
    with %SalesInvoices.SalesInvoice{} <- sales_invoice do
      Bodyguard.permit!(SalesInvoices, :show, conn.assigns.current_user, sales_invoice)
    end

    render_sales_invoice(conn, sales_invoice)
  end

  defp render_sales_invoice(conn, %SalesInvoices.SalesInvoice{} = sales_invoice) do
    sales_invoice = sales_invoice |> Repo.preload([:corrected_invoice]) |> SalesInvoices.populate_reference_invoices()

    render(conn, :sales_invoice,
      layout: false,
      sales_invoice: sales_invoice,
      currency_rate: SalesInvoices.get_currency_rate(sales_invoice),
      reference_invoice: sales_invoice.reference_invoice,
      class: "mx-auto",
      show_vat: conn.assigns.current_org.is_vat_payer,
      logo_data_uri: nil,
      footer_logo_data_uri: nil
    )
  end

  defp render_sales_invoice(conn, nil) do
    send_resp(conn, 404, "Not found")
  end

  def pdf(conn, %{"id" => id}) do
    case SalesInvoices.get_sales_invoice_with_logo_url(id) do
      nil ->
        send_resp(conn, 404, "Not found")

      sales_invoice ->
        Bodyguard.permit!(SalesInvoices, :show, conn.assigns.current_user, sales_invoice)

        sales_invoice = Repo.preload(sales_invoice, [:corrected_invoice])

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
