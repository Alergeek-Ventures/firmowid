defmodule FirmowidWeb.Infrastructure.Controllers.FileDownload do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.SalesInvoices
  alias FirmowidWeb.Core.Endpoint

  require Logger

  def batch(conn, params) do
    month = Date.from_iso8601!(params["month"])

    include_digital = params["include_digital"] == "true"
    include_ksef = params["include_ksef"] == "true"
    include_photos = params["include_photos"] == "true"
    include_sales = params["include_sales"] == "true"

    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    # TODO: replace authorize?: false + actor: %{} with system actor once available
    cost_invoices =
      date_range_from
      |> AshCostInvoice.list_invoices_in_date_range!(date_range_to,
        tenant: conn.assigns.current_user.organization_id,
        authorize?: false,
        actor: %{}
      )
      |> Enum.filter(&include_cost_invoice?(&1, include_digital, include_ksef, include_photos))
      |> Enum.map(fn document ->
        blob_url = document.blob.url

        file_extension =
          blob_url
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
          source: {:url, blob_url},
          path: "kosztowe/#{file_name}#{file_extension}"
        ]
      end)

    sales_invoices =
      if include_sales do
        date_range_from
        |> SalesInvoices.list_invoices_in_date_range(date_range_to)
        |> Enum.map(fn invoice ->
          file_name = clean_filename("#{invoice.invoice_number}_#{SalesInvoices.buyer_display_name(invoice)}")

          url_with_protocol = Endpoint.url()
          download_path = ~p"/sprzedazowe/#{invoice.id}/pobierz"

          [
            source:
              {:url,
               {"#{url_with_protocol}/#{download_path}",
                [headers: [{"cookie", "_firmowid_key=#{conn.cookies["_firmowid_key"]}"}]]}},
            path: "sprzedazowe/#{file_name}.pdf"
          ]
        end)
      else
        []
      end

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

  defp include_cost_invoice?(invoice, include_digital, include_ksef, include_photos) do
    extension =
      invoice.blob.url
      |> String.split("?")
      |> hd()
      |> Path.extname()
      |> String.downcase()

    case extension do
      ".pdf" -> include_digital
      ".xml" -> include_ksef
      _image -> include_photos
    end
  end

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
