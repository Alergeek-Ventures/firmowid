defmodule FirmowidWeb.Infrastructure.Controllers.FileDownload do
  @moduledoc false
  use FirmowidWeb, :controller

  alias Firmowid.Ash.Invoicing.Services.MonthDownloadEntries
  alias FirmowidWeb.Core.Endpoint

  require Ash.Query
  require Logger

  def batch(conn, params) do
    month = Date.from_iso8601!(params["month"])

    include_digital = params["include_digital"] == "true"
    include_ksef = params["include_ksef"] == "true"
    include_photos = params["include_photos"] == "true"
    include_sales = params["include_sales"] == "true"

    include_opts = %{
      include_digital: include_digital,
      include_ksef: include_ksef,
      include_photos: include_photos,
      include_sales: include_sales
    }

    entries =
      MonthDownloadEntries.build(
        month,
        include_opts,
        conn.assigns.ash_scope,
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

  defdelegate clean_filename(filename), to: MonthDownloadEntries
end
