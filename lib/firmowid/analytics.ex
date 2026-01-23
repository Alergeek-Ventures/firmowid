defmodule Firmowid.Analytics do
  @moduledoc """
  Unified analytics interface for Firmowid.

  Dispatches analytics events to enabled backends:
  - PostHog (when POSTHOG_ENABLED=true) - custom events, pageviews, user identification
  - PhoenixAnalytics (when PHOENIX_ANALYTICS_ENABLED=true) - request tracking with local dashboard

  ## Configuration

  Set via environment variables (read at boot in runtime.exs):
  - `PHOENIX_ANALYTICS_ENABLED` - defaults to "true"
  - `POSTHOG_ENABLED` - defaults to "false"
  - `POSTHOG_API_KEY` - required when PostHog enabled
  - `POSTHOG_API_HOST` - defaults to "https://eu.i.posthog.com"

  ## Usage

      # Track a custom business event (PostHog only)
      Analytics.track_event("invoice_created", user, %{amount: 100})

      # Track a pageview (both backends, called from plug)
      conn = Analytics.track_request(conn)

      # Identify a user (PostHog only)
      Analytics.identify(user)
  """

  import Plug.Conn

  alias PhoenixAnalytics.Plugs.RequestTracker

  # Cookie name used by PhoenixAnalytics for session tracking.
  # We reuse it to maintain consistent anonymous user identity across both backends.
  @phoenix_analytics_session_cookie "pa_session_id"

  @anonymous_id "anonymous"

  @doc """
  Tracks an HTTP request.

  Registers before_send callbacks on the conn to track the request
  in enabled backends (PhoenixAnalytics, PostHog).

  Called from the AnalyticsTracker plug.
  """
  @spec track_request(Plug.Conn.t()) :: Plug.Conn.t()
  def track_request(conn) do
    conn
    |> maybe_track_phoenix_analytics()
    |> maybe_track_posthog_pageview()
  end

  @doc """
  Tracks a custom business event.

  Only dispatches to PostHog (PhoenixAnalytics doesn't support custom events).

  ## Examples

      Analytics.track_event("invoice_created", user, %{amount: 100, currency: "PLN"})
      Analytics.track_event("user_signed_up", user)
  """
  @spec track_event(String.t(), map() | struct(), map()) :: :ok
  def track_event(event_name, user, properties \\ %{}) do
    if posthog_enabled?() do
      distinct_id = get_distinct_id(user)
      safe_posthog_capture(event_name, distinct_id, properties)
    end

    :ok
  end

  @doc """
  Identifies a user to analytics backends.

  Sets user properties in PostHog for future event attribution.

  ## Examples

      Analytics.identify(user)
      Analytics.identify(user, %{plan: "pro", company: "Acme"})
  """
  @spec identify(map() | struct(), map()) :: :ok
  def identify(user, properties \\ %{}) do
    if posthog_enabled?() do
      distinct_id = get_distinct_id(user)

      user_properties =
        %{
          email: Map.get(user, :email),
          name: Map.get(user, :name)
        }
        |> Map.merge(properties)
        |> compact_map()

      safe_posthog_capture("$identify", distinct_id, %{"$set" => user_properties})
    end

    :ok
  end

  @doc """
  Returns whether PhoenixAnalytics is enabled.
  """
  @spec phoenix_analytics_enabled?() :: boolean()
  def phoenix_analytics_enabled? do
    get_config(:phoenix_analytics_enabled, true)
  end

  @doc """
  Returns whether PostHog is enabled.
  """
  @spec posthog_enabled?() :: boolean()
  def posthog_enabled? do
    get_config(:posthog_enabled, false)
  end

  defp maybe_track_phoenix_analytics(conn) do
    if phoenix_analytics_enabled?() do
      RequestTracker.call(conn, RequestTracker.init([]))
    else
      conn
    end
  end

  defp maybe_track_posthog_pageview(conn) do
    if posthog_enabled?() and html_request?(conn) do
      register_before_send(conn, &capture_posthog_pageview/1)
    else
      conn
    end
  end

  defp capture_posthog_pageview(conn) do
    if conn.status in 200..399, do: do_capture_posthog_pageview(conn)
    conn
  end

  defp do_capture_posthog_pageview(conn) do
    distinct_id = get_distinct_id_from_conn(conn)

    properties = %{
      "$current_url" => current_url(conn),
      "$pathname" => conn.request_path,
      "$host" => conn.host,
      "$referrer" => get_referrer(conn)
    }

    safe_posthog_capture("$pageview", distinct_id, properties)
  end

  # Wraps PostHog.bare_capture in try/rescue to ensure analytics failures
  # never impact request processing. Analytics is non-critical.
  defp safe_posthog_capture(event, distinct_id, properties) do
    PostHog.bare_capture(event, distinct_id, properties)
  rescue
    _error -> :ok
  end

  defp html_request?(conn) do
    accept = conn |> get_req_header("accept") |> List.first() || ""
    String.contains?(accept, "text/html")
  end

  defp current_url(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    port_suffix = if conn.port in [80, 443], do: "", else: ":#{conn.port}"
    query_suffix = if conn.query_string == "", do: "", else: "?#{conn.query_string}"
    "#{scheme}://#{conn.host}#{port_suffix}#{conn.request_path}#{query_suffix}"
  end

  defp get_referrer(conn) do
    conn |> get_req_header("referer") |> List.first() || ""
  end

  defp get_distinct_id(user) when is_map(user) do
    Map.get(user, :id) || Map.get(user, "id") || @anonymous_id
  end

  defp get_distinct_id_from_conn(conn) do
    cond do
      user = conn.assigns[:current_user] ->
        get_distinct_id(user)

      session_id = conn.cookies[@phoenix_analytics_session_cookie] ->
        "anon_#{session_id}"

      true ->
        @anonymous_id
    end
  end

  defp get_config(key, default) do
    :firmowid
    |> Application.get_env(:analytics, [])
    |> Keyword.get(key, default)
  end

  defp compact_map(map) do
    Map.filter(map, fn {_k, v} -> not is_nil(v) end)
  end
end
