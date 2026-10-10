defmodule FirmowidWeb.Mcp.Runtime do
  @moduledoc "Shared MCP App shell, resource metadata and authenticated native LiveView mounts."
  use FirmowidWeb, :html

  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.DesignSystem.Components.Button
  alias FirmowidWeb.Mcp.Session

  @doc "Renders the standalone shell using the same compiled styles as the web application."
  @spec document() :: String.t()
  def document do
    assigns = %{
      css: stylesheet(),
      javascript: javascript(),
      messages: messages() |> Jason.encode!() |> String.replace("<", "\\u003c")
    }

    ~H"""
    <!DOCTYPE html>
    <html lang="pl" class="font-sans">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Firmowid</title>
        <style>
          <%= Phoenix.HTML.raw(@css) %>
        </style>
      </head>
      <body class="bg-lightGreyBg text-grey-900">
        <div class="flex items-center justify-between gap-3 p-3">
          <p id="mcp-status" role="status" aria-live="polite">{gettext("Connecting…")}</p>
          <Button.button id="mcp-refresh" type="button" size="small" variant="outline" disabled>
            {gettext("Reconnect")}
          </Button.button>
        </div>
        <div id="mcp-root"></div>
        <script id="mcp-messages" type="application/json">
          <%= Phoenix.HTML.raw(@messages) %>
        </script>
        <script>
          <%= Phoenix.HTML.raw(@javascript) %>
        </script>
      </body>
    </html>
    """
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc "Places the signed mount exclusively in tool-result metadata, never model-visible content."
  @spec mount_metadata(Plug.Conn.t(), module(), map()) :: map()
  def mount_metadata(conn, app, arguments) do
    token = Session.issue(conn, app.resource_uri(), Map.get(arguments, "input", %{}))

    html =
      conn
      |> Phoenix.Component.live_render(app.live_view(), session: %{"mcp_session" => token})
      |> Phoenix.HTML.safe_to_string()

    %{
      "version" => 1,
      "html" => html,
      "socket_url" => socket_url(),
      "resource_uri" => app.resource_uri(),
      "tool_name" => app.tool_name(),
      "arguments" => arguments
    }
  end

  @doc "Returns standard MCP Apps CSP and the ChatGPT compatibility representation."
  @spec resource_metadata() :: map()
  def resource_metadata do
    origin = Endpoint.url()
    websocket_origin = origin |> URI.parse() |> websocket_uri() |> URI.to_string()
    connect = [origin, websocket_origin]

    %{
      "ui" => %{
        "prefersBorder" => true,
        "csp" => %{"connectDomains" => connect, "resourceDomains" => [origin]}
      },
      "openai/widgetCSP" => %{"connect_domains" => connect, "resource_domains" => [origin]}
    }
  end

  defp socket_url do
    Endpoint.url()
    |> URI.parse()
    |> websocket_uri()
    |> Map.put(:path, "/mcp/live")
    |> URI.to_string()
  end

  defp websocket_uri(%URI{scheme: "https"} = uri), do: %{uri | scheme: "wss"}
  defp websocket_uri(%URI{scheme: "http"} = uri), do: %{uri | scheme: "ws"}

  defp messages do
    %{
      connecting: gettext("Connecting…"),
      connected: gettext("Connected"),
      disconnected: gettext("Connection lost. Reconnecting…"),
      failed: gettext("Connection failed. Try refreshing."),
      expired: gettext("Session expired. Refresh to reconnect."),
      context_failed: gettext("The view is current, but ChatGPT could not receive its context."),
      blocked: gettext("The browser blocked the connection. Check network permissions.")
    }
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Both paths identify fixed build artifacts in application priv, including releases.
  defp stylesheet do
    :firmowid
    |> Application.app_dir("priv/static/assets/app.css")
    |> File.read!()
    |> inline_fonts()
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Fixed release assets only. Data URLs avoid cross-origin font requests in the sandbox.
  defp inline_fonts(css) do
    Enum.reduce(
      ~w(lexend-latin-ext lexend-latin josefin-sans-700-latin-ext josefin-sans-700-latin nothing-you-could-do-latin),
      css,
      fn name, css ->
        font = :firmowid |> Application.app_dir("priv/static/fonts/#{name}.woff2") |> File.read!()

        String.replace(
          css,
          "/fonts/#{name}.woff2",
          "data:font/woff2;base64," <> Base.encode64(font)
        )
      end
    )
  end

  # sobelow_skip ["Traversal.FileModule"]
  # No request input enters this fixed build-artifact path or trusted inline script.
  defp javascript do
    :firmowid
    |> Application.app_dir("priv/static/assets/mcp.js")
    |> File.read!()
    |> String.replace("</script", "<\\/script")
  end
end
