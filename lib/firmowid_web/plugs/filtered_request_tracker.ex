defmodule FirmowidWeb.Plugs.FilteredRequestTracker do
  @moduledoc """
  Analytics tracking plug that filters out requests to certain paths.

  Delegates to `Firmowid.Analytics.track_request/1` which dispatches to
  enabled backends (PhoenixAnalytics, PostHog).

  ## Configuration

  The plug can be configured with the following options:

    * `:ignore_paths` - a list of path prefixes to ignore (default: ["/admin", "/health"])

  ## Usage

      plug FirmowidWeb.Plugs.FilteredRequestTracker

  Or with custom ignored paths:

      plug FirmowidWeb.Plugs.FilteredRequestTracker, ignore_paths: ["/admin", "/health", "/metrics"]
  """

  @behaviour Plug

  alias Firmowid.Analytics

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
      Analytics.track_request(conn)
    end
  end

  defp ignored_path?(request_path, ignore_paths) do
    Enum.any?(ignore_paths, fn prefix ->
      String.starts_with?(request_path, prefix)
    end)
  end
end
