defmodule FirmowidWeb.FileController do
  use FirmowidWeb, :controller

  alias Firmowid.CostInvoices
  alias Firmowid.SalesInvoices

  require Logger

  def batch(conn, params) do
    month = Date.from_iso8601!(params["month"])
    skip_scans = params["skip_scans"] == "true"

    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    cost_invoices =
      date_range_from
      |> CostInvoices.list_invoices_in_date_range(date_range_to)
      |> Enum.filter(fn invoice -> !skip_scans || String.contains?(invoice.file_url, ".pdf") end)
      |> Enum.map(fn document ->
        file_extension =
          document.file_url
          # drop S3 postfix (?AMZ...)
          |> String.split("?")
          |> hd()
          |> Path.extname()

        # append part of SHA256 hash to avoid filename collisions
        file_name =
          clean_filename(
            "#{document.issue_date}_#{document.seller_display_name}_#{String.slice(document.blob.blob_checksum, 0, 8)}"
          )

        [
          source: {:url, document.file_url},
          path: "kosztowe/#{file_name}#{file_extension}"
        ]
      end)

    sales_invoices =
      date_range_from
      |> SalesInvoices.list_invoices_in_date_range(date_range_to)
      |> Enum.map(fn invoice ->
        file_name = clean_filename("#{invoice.invoice_number}_#{SalesInvoices.buyer_display_name(invoice)}")

        url_with_protocol = FirmowidWeb.Endpoint.url()
        download_path = ~p"/sprzedazowe/#{invoice.id}/pobierz"

        [
          source:
            {:url,
             {"#{url_with_protocol}/#{download_path}",
              [
                {
                  "Cookie",
                  "_firmowid_key=#{conn.cookies["_firmowid_key"]}"
                }
              ], []}},
          path: "sprzedazowe/#{file_name}.pdf"
        ]
      end)

    entries = cost_invoices ++ sales_invoices

    Logger.info(
      "Batch download starting: #{length(cost_invoices)} cost invoices, #{length(sales_invoices)} sales invoices"
    )

    stream = Packmatic.build_stream(entries, on_event: &log_packmatic_event/1)

    Packmatic.Conn.send_chunked(
      stream,
      conn,
      "#{Calendar.strftime(month, "%Y-%m")}-dokumenty.zip"
    )
  end

  defp log_packmatic_event(%Packmatic.Event.EntryStarted{entry: entry}) do
    Logger.info("Packmatic: starting #{entry.path}")
    :ok
  end

  defp log_packmatic_event(%Packmatic.Event.EntryCompleted{entry: entry}) do
    Logger.info("Packmatic: completed #{entry.path}")
    :ok
  end

  defp log_packmatic_event(%Packmatic.Event.EntryFailed{entry: entry, reason: reason}) do
    Logger.error("Packmatic: FAILED #{entry.path} - reason: #{inspect(reason)}")
    :ok
  end

  defp log_packmatic_event(%Packmatic.Event.StreamEnded{reason: reason, stream_bytes_emitted: bytes}) do
    Logger.info("Packmatic: stream ended - reason: #{inspect(reason)}, bytes: #{bytes}")
    :ok
  end

  defp log_packmatic_event(_event), do: :ok

  def clean_filename(filename) do
    filename
    |> AnyAscii.transliterate()
    |> IO.iodata_to_binary()
    # drop all weird chars
    |> String.downcase()
    |> String.trim()
    |> String.replace(" ", "_")
    |> String.replace(".", "_")
    |> String.replace("/", "_")
  end
end
