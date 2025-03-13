defmodule FirmowidWeb.FileController do
  use FirmowidWeb, :controller

  alias Firmowid.SalesInvoices
  alias Firmowid.CostInvoices

  def batch(conn, params) do
    month = params["month"] |> Date.from_iso8601!()
    skip_scans = params["skip_scans"] == "true"

    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    cost_invoices =
      CostInvoices.list_invoices_issued_in_date_range(
        date_range_from,
        date_range_to
      )
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
          "#{document.issue_date}_#{document.seller_display_name}_#{document.blob.blob_checksum |> String.slice(0, 8)}"
          |> clean_filename()

        [
          source: {:url, document.file_url},
          path: "kosztowe/#{file_name}#{file_extension}"
        ]
      end)

    sales_invoices =
      SalesInvoices.list_invoices_issued_in_date_range(
        date_range_from,
        date_range_to
      )
      |> Enum.map(fn invoice ->
        file_name =
          "#{invoice.invoice_number}_#{invoice.buyer_display_name}" |> clean_filename()

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

    stream =
      (cost_invoices ++ sales_invoices)
      |> Packmatic.build_stream()

    Packmatic.Conn.send_chunked(
      stream,
      conn,
      "#{month |> Calendar.strftime("%Y-%m")}-dokumenty.zip"
    )
  end

  defp clean_filename(filename) do
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
