defmodule FirmowidWeb.Infrastructure.Plugs.AnalyticsDashboardGuard do
  @moduledoc """
  Guards the PhoenixAnalytics dashboard route.

  When PhoenixAnalytics is disabled (PHOENIX_ANALYTICS_ENABLED=false),
  this plug renders a "disabled" message instead of the dashboard.

  Only activates for paths starting with `/admin/analytics`.
  """

  @behaviour Plug

  import Plug.Conn

  alias Firmowid.Analytics

  @impl true
  def init(opts), do: opts

  # sobelow_skip ["XSS.SendResp"]
  # Response body is a hardcoded HTML string literal (disabled_html/0), no user input interpolated.
  @impl true
  def call(conn, _opts) do
    if analytics_path?(conn) and not Analytics.phoenix_analytics_enabled?() do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, disabled_html())
      |> halt()
    else
      conn
    end
  end

  defp analytics_path?(conn) do
    String.starts_with?(conn.request_path, "/admin/analytics")
  end

  defp disabled_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Analytics Dashboard</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
          margin: 0;
          background-color: #f5f5f5;
        }
        .container {
          text-align: center;
          padding: 2rem;
          background: white;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
          max-width: 400px;
        }
        h1 { color: #333; margin-bottom: 0.5rem; }
        p { color: #666; }
        code {
          background: #f0f0f0;
          padding: 0.2rem 0.4rem;
          border-radius: 4px;
          font-size: 0.9em;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Analytics Dashboard Disabled</h1>
        <p>PhoenixAnalytics is not enabled for this instance.</p>
        <p>Set <code>PHOENIX_ANALYTICS_ENABLED=true</code> to enable.</p>
      </div>
    </body>
    </html>
    """
  end
end
