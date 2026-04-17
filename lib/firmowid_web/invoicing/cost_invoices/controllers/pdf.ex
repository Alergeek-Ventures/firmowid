defmodule FirmowidWeb.Invoicing.CostInvoices.Controllers.Pdf do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.Services.CostInvoicePdf
  alias Firmowid.Ash.Invoicing.Services.MonthDownloadEntries

  def pdf(conn, %{"id" => id}) do
    include_internal_note = Map.get(conn.params, "include_internal_note", "true") == "true"

    case CostInvoice.by_id(id, scope: conn.assigns.ash_scope) do
      {:ok, invoice} ->
        case CostInvoicePdf.generate(invoice,
               scope: conn.assigns.ash_scope,
               include_internal_note: include_internal_note
             ) do
          {:ok, pdf_binary} ->
            filename = cost_invoice_filename(invoice, conn.assigns.ash_scope)

            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, pdf_binary)

          {:error, _reason} ->
            send_resp(conn, 500, "PDF generation failed")
        end

      {:error, _reason} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp cost_invoice_filename(invoice, scope) do
    invoice =
      Ash.load!(invoice, [:effective_seller_display_name, blob: [:blob_checksum]], scope: scope)

    MonthDownloadEntries.clean_filename(
      "#{invoice.issue_date}_#{invoice.effective_seller_display_name}_#{String.slice(invoice.blob.blob_checksum, 0, 8)}"
    ) <> ".pdf"
  end
end
