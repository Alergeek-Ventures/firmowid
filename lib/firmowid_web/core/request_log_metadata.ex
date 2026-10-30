defmodule FirmowidWeb.Core.RequestLogMetadata do
  @moduledoc """
  Adds logger metadata used to filter HTTP request logs in Sentry.

  The metadata is set before `Plug.Telemetry` runs so Phoenix request and
  response logs inherit it.
  """

  @behaviour Plug

  @health_path "/health"

  @doc "Disables Phoenix request logs for paths carrying authentication credentials."
  @spec log_level(Plug.Conn.t()) :: :info | false
  def log_level(%{path_info: [segment | _]}) do
    if URI.decode(segment) in ["resetuj-haslo", "potwierdz-email"], do: false, else: :info
  end

  def log_level(_conn), do: :info

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
    Firmowid.Sentry.clear_password_login_context()
    Logger.metadata(health_check: conn.request_path == @health_path)
    conn
  end
end
