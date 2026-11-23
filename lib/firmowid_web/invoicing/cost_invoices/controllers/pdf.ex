defmodule FirmowidWeb.Invoicing.CostInvoices.Controllers.Pdf do
  @moduledoc "Serves authorized cost-invoice PDFs and complete correction archives."
  use FirmowidWeb, :controller

  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.Services.CostInvoicePdf
  alias Firmowid.Invoicing.Services.MonthDownloadEntries
  alias FirmowidWeb.Invoicing.Utilities.InvoiceDownloadParams

  def pdf(conn, params), do: send_pdf(conn, params, :attachment)

  def preview(conn, params), do: send_pdf(conn, params, :inline)

  def archive(conn, %{"id" => id}) do
    opts = [
      scope: conn.assigns.ash_scope,
      include_internal_note: InvoiceDownloadParams.parse_include_internal_note(conn.params)
    ]

    with {:ok, invoice} <- CostInvoice.by_id(id, scope: conn.assigns.ash_scope),
         {:ok, [root | _] = invoices} <-
           CostInvoice.pdf_family(invoice, scope: conn.assigns.ash_scope),
         {:ok, entries} <- archive_entries(invoices, opts),
         {:ok, {_name, binary}} <- :zip.create(~c"faktury.zip", entries, [:memory]) do
      send_download(conn, {:binary, binary},
        filename: archive_basename(root) <> ".zip",
        content_type: "application/zip"
      )
    else
      {:error, %Ash.Error.Invalid{}} -> send_resp(conn, 404, "Not found")
      {:error, %Ash.Error.Forbidden{}} -> send_resp(conn, 404, "Not found")
      {:error, :missing_original_invoice} -> send_resp(conn, 422, "Original invoice unavailable")
      {:error, :cyclic_invoice_family} -> send_resp(conn, 422, "Invalid invoice family")
      {:error, _reason} -> send_resp(conn, 500, "PDF generation failed")
    end
  end

  defp archive_entries(invoices, opts) do
    invoices
    |> Enum.reduce_while({:ok, []}, fn invoice, {:ok, entries} ->
      case CostInvoicePdf.generate(invoice, opts) do
        {:ok, binary} ->
          entry = {String.to_charlist(archive_basename(invoice) <> ".pdf"), binary}
          {:cont, {:ok, [entry | entries]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp archive_basename(invoice) do
    # The UUID prevents collisions; the allowlist keeps entry names flat on every platform.
    "#{invoice.issue_date}_#{invoice.invoice_identifier}_#{invoice.id}"
    |> MonthDownloadEntries.clean_filename()
    |> String.replace(~r/[^a-z0-9_-]/, "_")
  end

  # sobelow_skip ["XSS.SendResp"]
  # Generated PDF bytes are served with application/pdf, never as HTML.
  defp send_pdf(conn, %{"id" => id}, disposition) do
    include_internal_note = InvoiceDownloadParams.parse_include_internal_note(conn.params)

    case CostInvoice.by_id(id, scope: conn.assigns.ash_scope) do
      {:ok, invoice} ->
        case CostInvoicePdf.generate(invoice,
               scope: conn.assigns.ash_scope,
               include_internal_note: include_internal_note
             ) do
          {:ok, pdf_binary} ->
            filename = cost_invoice_filename(invoice, conn.assigns.ash_scope)

            send_download(conn, {:binary, pdf_binary},
              disposition: disposition,
              filename: filename,
              content_type: "application/pdf"
            )

          {:error, _reason} ->
            send_resp(conn, 500, "PDF generation failed")
        end

      {:error, _reason} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp cost_invoice_filename(invoice, scope) do
    invoice =
      Ash.load!(invoice, [:effective_seller_display_name, :blob], scope: scope)

    suffix = if invoice.blob, do: String.slice(invoice.blob.blob_checksum, 0, 8), else: invoice.id

    MonthDownloadEntries.clean_filename("#{invoice.issue_date}_#{invoice.effective_seller_display_name}_#{suffix}") <>
      ".pdf"
  end
end
