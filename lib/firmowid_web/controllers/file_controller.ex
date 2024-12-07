defmodule FirmowidWeb.FileController do
  use FirmowidWeb, :controller

  alias Firmowid.Documents

  def batch(conn, params) do
    user = conn.assigns.current_user
    organization_id = user.organization_id

    month = params["month"] |> Date.from_iso8601!()

    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    documents =
      Documents.list_documents_issued_by_with_metadata(
        organization_id,
        date_range_from,
        date_range_to
      )

    stream =
      documents
      |> Enum.map(fn document ->
        file_extension =
          document.file_url
          # drop S3 postfix (?AMZ...)
          |> String.split("?")
          |> hd()
          |> Path.extname()

        file_name =
          document.invoice_identifier
          # drop all weird chars
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
