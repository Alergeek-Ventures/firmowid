defmodule FirmowidWeb.Plugs.FilteredRequestTracker do
  @moduledoc """
  A wrapper around PhoenixAnalytics.Plugs.RequestTracker that filters out
  requests to certain paths from being tracked.

  This plug delegates to the original RequestTracker for all requests except
  those matching the ignored path patterns.

  ## Configuration

  The plug can be configured with the following options:

    * `:ignore_paths` - a list of path prefixes to ignore (default: ["/admin", "/health"])

  ## Usage

      plug FirmowidWeb.Plugs.FilteredRequestTracker

  Or with custom ignored paths:

      plug FirmowidWeb.Plugs.FilteredRequestTracker, ignore_paths: ["/admin", "/health", "/metrics"]
  """

  @behaviour Plug

  alias PhoenixAnalytics.Plugs.RequestTracker

  @default_ignore_paths ["/admin", "/health"]

  @impl true
  def init(opts) do
    ignore_paths = Keyword.get(opts, :ignore_paths, @default_ignore_paths)
    %{ignore_paths: ignore_paths}
  end

  @impl true
  def call(conn, %{ignore_paths: ignore_paths}) do
    if ignored_path?(conn.request_path, ignore_paths) do
      conn
    else
      RequestTracker.call(
        conn,
        RequestTracker.init([])
      )
    end
  end

  defp ignored_path?(request_path, ignore_paths) do
    Enum.any?(ignore_paths, fn prefix ->
      String.starts_with?(request_path, prefix)
    end)
  end
end
