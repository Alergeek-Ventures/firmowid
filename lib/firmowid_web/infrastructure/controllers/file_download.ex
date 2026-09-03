defmodule FirmowidWeb.Infrastructure.Controllers.FileDownload do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing.Services.MonthDownloadEntries
  alias Firmowid.ErrorKind
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams
  alias FirmowidWeb.Invoicing.Utilities.InvoiceDownloadParams
  alias FirmowidWeb.Invoicing.Utilities.MonthDownloadPackmatic

  require Logger

  def batch(conn, params) do
    case QueryParams.parse_date(params, "miesiac", nil) do
      %Date{} = month ->
        include_opts = InvoiceDownloadParams.parse_batch_options(params)
        include_internal_note = Map.get(include_opts, :include_internal_note, true)

        selection_opts =
          Map.take(include_opts, [
            :include_digital,
            :include_ksef,
            :include_photos,
            :include_sales
          ])

        entries =
          month
          |> MonthDownloadEntries.build(selection_opts, conn.assigns.ash_scope)
          |> MonthDownloadPackmatic.build_entries(
            include_internal_note,
            conn.cookies["_firmowid_key"],
            Endpoint.url()
          )

        Logger.info("Batch download starting: #{length(entries)} entries")

        stream = Packmatic.build_stream(entries, on_event: &log_packmatic_event/1)

        Packmatic.Conn.send_chunked(
          stream,
          conn,
          "#{Calendar.strftime(month, "%Y-%m")}-dokumenty.zip"
        )

      nil ->
        send_resp(conn, 400, "Nieprawidłowy parametr miesiąca.")
    end
  end

  defp log_packmatic_event(%Packmatic.Event.EntryStarted{entry: _entry}) do
    Logger.info("Packmatic: entry starting")
    :ok
  end

  defp log_packmatic_event(%Packmatic.Event.EntryCompleted{entry: _entry}) do
    Logger.info("Packmatic: entry completed")
    :ok
  end

  defp log_packmatic_event(%Packmatic.Event.EntryFailed{entry: _entry, reason: reason}) do
    Logger.error("Packmatic: entry failed", error_kind: ErrorKind.classify(reason))
    :ok
  end

  defp log_packmatic_event(%Packmatic.Event.StreamEnded{reason: reason, stream_bytes_emitted: bytes}) do
    Logger.info("Packmatic: stream ended", status: ErrorKind.classify(reason), bytes: bytes)
    :ok
  end

  defp log_packmatic_event(_event), do: :ok

  defdelegate clean_filename(filename), to: MonthDownloadEntries
end
