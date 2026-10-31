defmodule FirmowidMcp.Runtime do
  @moduledoc "Shared MCP App shell, resource metadata and authenticated native LiveView mounts."
  use FirmowidUI, :html

  alias FirmowidMcp.Session

  @locales Gettext.known_locales(Firmowid.Gettext)

  @doc "Renders the standalone shell using the same compiled styles as the web application."
  @spec document() :: String.t()
  # sobelow_skip ["XSS.Raw"]
  # CSS/JS are fixed release assets; messages are Gettext strings encoded as JSON
  # with HTML delimiters escaped. No request data or invoice content enters this document.
  def document do
    assigns = %{
      css: stylesheet(),
      javascript: javascript(),
      messages: messages() |> Jason.encode!() |> String.replace("<", "\\u003c")
    }

    ~H"""
    <!DOCTYPE html>
    <html lang="pl">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Firmowid</title>
        <style>
          <%= Phoenix.HTML.raw(@css) %>
          /* ChatGPT can wrap the root in an element with its own font, which plain text would inherit. */
          body, #mcp-root, #mcp-status, button, input, select, textarea { font-family: "Lexend", ui-sans-serif, system-ui, sans-serif !important; }
          #mcp-root, #mcp-status { inline-size: min(100%, 34rem); margin-inline: auto; }
          #mcp-root:has(#mcp-invoice-issuance) { inline-size: min(100%, 72rem); }
        </style>
      </head>
      <body class="bg-grey-100 text-grey-900">
        <p id="mcp-status" role="status" aria-live="polite" class="p-4" hidden></p>
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

  @doc "Addresses the public HTML, bundled assets and resource metadata by their content."
  @spec resource_uri(module()) :: String.t()
  @spec resource_uri(module(), String.t()) :: String.t()
  def resource_uri(app, html \\ document()) do
    digest =
      {html, resource_metadata(app)}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    String.trim_trailing(app.resource_uri(), ".html") <> "-" <> digest <> ".html"
  end

  @doc "Describes the optional `language` argument of widget tools."
  @spec language_schema() :: map()
  def language_schema do
    %{
      "type" => "string",
      "enum" => @locales,
      "description" =>
        "Language of the widget interface, for example the language of the conversation. " <>
          "Omit it to use the language set in the user's Firmowid account."
    }
  end

  @doc """
  Places the signed mount exclusively in tool-result metadata, never model-visible content.

  The widget uses the language the `language` argument requests, otherwise the one set in the
  user's account.
  """
  @spec mount_metadata(Plug.Conn.t(), module(), map()) :: map()
  def mount_metadata(conn, app, arguments) do
    # AshAi ignores top-level arguments outside its own schema, so the tool ran without it.
    {language, arguments} = Map.pop(arguments, "language")
    locale = locale(conn, language)
    token = Session.issue(conn, app.resource_uri(), arguments)

    # The widget's mount also puts its language in this process; with_locale restores the caller's.
    {html, messages} =
      Gettext.with_locale(Firmowid.Gettext, locale, fn ->
        Firmowid.Cldr.with_locale(locale, fn ->
          html =
            conn
            |> Phoenix.Component.live_render(app.live_view(),
              session: %{
                "mcp_session" => token,
                "mcp_resource" => app.resource_uri(),
                "mcp_locale" => locale
              }
            )
            |> Phoenix.HTML.safe_to_string()

          {html, messages()}
        end)
      end)

    %{
      "version" => 1,
      "html" => html,
      "locale" => locale,
      "messages" => messages,
      "socket_url" => socket_url(),
      "resource_uri" => resource_uri(app),
      "tool_name" => app.tool_name(),
      "arguments" => arguments
    }
  end

  defp locale(_conn, language) when language in @locales, do: language

  defp locale(conn, _language) do
    case Ash.PlugHelpers.get_actor(conn).locale do
      nil -> Gettext.get_locale(Firmowid.Gettext)
      locale -> Atom.to_string(locale)
    end
  end

  @doc "Returns standard MCP Apps CSP and the ChatGPT compatibility representation."
  @spec resource_metadata(module()) :: map()
  def resource_metadata(app) do
    origin = FirmowidMcp.endpoint().url()
    websocket_origin = origin |> URI.parse() |> websocket_uri() |> URI.to_string()
    connect = [origin, websocket_origin]

    %{
      "ui" => %{
        "prefersBorder" => true,
        "csp" => %{"connectDomains" => connect, "resourceDomains" => [origin]}
      },
      "openai/widgetCSP" => %{"connect_domains" => connect, "resource_domains" => [origin]},
      "openai/widgetDescription" => app.widget_description()
    }
  end

  defp socket_url do
    FirmowidMcp.endpoint().url()
    |> URI.parse()
    |> websocket_uri()
    |> Map.put(:path, "/mcp/live")
    |> URI.to_string()
  end

  defp websocket_uri(%URI{scheme: "https"} = uri), do: %{uri | scheme: "wss"}
  defp websocket_uri(%URI{scheme: "http"} = uri), do: %{uri | scheme: "ws"}

  defp messages do
    %{
      failed: gettext("This view is unavailable."),
      expired: gettext("This view is unavailable."),
      context_failed: gettext("The view is current, but ChatGPT could not receive its context."),
      download_failed: gettext("The file could not be downloaded. Try again."),
      link_failed: gettext("Unable to open the link. Try again."),
      blocked: gettext("This view is unavailable.")
    }
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Both paths identify fixed build artifacts in application priv, including releases.
  defp stylesheet do
    :firmowid
    |> Application.app_dir("priv/static/assets/app.css")
    |> File.read!()
    |> String.replace("/fonts/", FirmowidMcp.endpoint().url() <> "/fonts/")
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
