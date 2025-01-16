defmodule FirmowidWeb.FileController do
  use FirmowidWeb, :controller

  alias Firmowid.Documents

  def batch(conn, params) do
    month = params["month"] |> Date.from_iso8601!()

    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    cost_invoices =
      Documents.list_invoices_issued_in_date_range(
        date_range_from,
        date_range_to
      )

    stream =
      cost_invoices
      |> Enum.map(fn document ->
        file_extension =
          document.file_url
          # drop S3 postfix (?AMZ...)
          |> String.split("?")
          |> hd()
          |> Path.extname()

        file_name =
          "#{document.issue_date}_#{document.seller_display_name}"
          # drop all weird chars
          |> String.downcase()
          |> String.trim()
          |> String.replace(" ", "_")
          |> String.replace(".", "_")
          |> String.replace("/", "_")

        [
          source: {:url, document.file_url},
          path: "#{month.year}-#{month.month}-dokumenty/#{file_name}#{file_extension}"
        ]
      end)
      |> Packmatic.build_stream()

    stream
    |> Packmatic.Conn.send_chunked(
      conn,
      "#{month.year}-#{month.month}-dokumenty.zip"
    )
  end
end
