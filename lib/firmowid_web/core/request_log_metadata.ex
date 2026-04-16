defmodule FirmowidWeb.Core.RequestLogMetadata do
  @moduledoc """
  Adds logger metadata used to filter HTTP request logs in Sentry.

  The metadata is set before `Plug.Telemetry` runs so Phoenix request and
  response logs inherit it.
  """

  @behaviour Plug

  require Logger

  @health_path "/health"

  @impl Plug
  @doc """
  Returns plug options unchanged.
  """
  @spec init(term()) :: term()
  def init(opts), do: opts

  @impl Plug
  @doc """
  Tags `/health` request logs so Sentry can filter them out.
  """
  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, _opts) do
    Logger.metadata(health_check: conn.request_path == @health_path)
    conn
  end
end
