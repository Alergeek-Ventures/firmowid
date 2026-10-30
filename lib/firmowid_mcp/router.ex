defmodule FirmowidMcp.Router do
  @moduledoc "Native AshAi MCP transport with feature-owned, optional LiveView presentations."
  @behaviour Plug

  import Plug.Conn

  alias AshAi.Mcp.Router, as: Transport
  alias FirmowidMcp.Invoicing.Privacy
  alias FirmowidMcp.Runtime
  alias FirmowidMcp.Widgets

  @security_schemes [%{"type" => "oauth2", "scopes" => ["mcp"]}]

  @impl true
  @doc "Initializes the explicit tool and resource allowlists."
  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts
    |> Keyword.put(:otp_app, :firmowid)
    |> Keyword.put(:mcp_name, "Firmowid")
    |> Keyword.put(:instructions, FirmowidMcp.instructions())
    |> Keyword.put(:tool_argument_transformer, &Privacy.validate_arguments/3)
    |> Transport.init()
  end

  @impl true
  @doc "Preserves native protocol validation/envelopes and decorates successful presentations."
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    context =
      Map.merge(
        Ash.PlugHelpers.get_context(conn) || %{},
        FirmowidMcp.Invoicing.action_context(),
        fn
          :shared, existing, required -> Map.merge(existing, required)
        end
      )

    conn
    |> Ash.PlugHelpers.set_context(context)
    |> put_resp_header("cache-control", "no-store")
    |> resolve_resource_request()
    |> register_before_send(&decorate_response/1)
    |> Transport.call(opts)
  end

  defp resolve_resource_request(conn) do
    body = resolve_resource_request_uri(conn.body_params)
    conn = %{conn | body_params: body, params: Map.merge(conn.params, body)}

    # The transport requires the Mcp-Name header to match the body URI, so resolve both.
    case {get_req_header(conn, "mcp-name"), body} do
      {[_name], %{"method" => "resources/read", "params" => %{"uri" => uri}}} ->
        put_req_header(conn, "mcp-name", uri)

      _other ->
        conn
    end
  end

  defp resolve_resource_request_uri(%{"_json" => requests} = body) when is_list(requests) do
    %{body | "_json" => Enum.map(requests, &resolve_resource_request_uri/1)}
  end

  defp resolve_resource_request_uri(%{"method" => "resources/read", "params" => %{"uri" => uri}} = body)
       when is_binary(uri) do
    # AshAi registers static URIs; expose content-addressed URIs at the transport boundary.
    case Enum.find(Widgets.all(), &(Runtime.resource_uri(&1) == uri)) do
      nil -> body
      app -> put_in(body, ["params", "uri"], app.resource_uri())
    end
  end

  defp resolve_resource_request_uri(body), do: body

  defp decorate_response(conn) do
    case Jason.decode(conn.resp_body || "") do
      {:ok, response} ->
        response = response |> decorate(conn.body_params, conn) |> put_server_icons()
        %{conn | resp_body: Jason.encode!(response)}

      _ ->
        conn
    end
  end

  defp decorate(responses, %{"_json" => requests}, conn) when is_list(responses) do
    Enum.map(responses, fn response ->
      request = Enum.find(requests, &(&1["id"] == response["id"])) || %{}
      decorate(response, request, conn)
    end)
  end

  defp decorate(%{"result" => %{"tools" => tools}} = response, _request, _conn) do
    put_in(response, ["result", "tools"], Enum.map(tools, &tool_metadata/1))
  end

  defp decorate(%{"result" => %{"capabilities" => capabilities}} = response, request, _conn) do
    params = request["params"] || %{}

    client =
      params["capabilities"] ||
        get_in(params, ["_meta", "io.modelcontextprotocol/clientCapabilities"]) || %{}

    mime_types = get_in(client, ["extensions", "io.modelcontextprotocol/ui", "mimeTypes"]) || []

    if is_list(mime_types) and "text/html;profile=mcp-app" in mime_types do
      capabilities = Map.update(capabilities, "extensions", %{}, & &1)

      put_in(
        response,
        ["result", "capabilities"],
        put_in(capabilities, ["extensions", "io.modelcontextprotocol/ui"], %{
          "mimeTypes" => ["text/html;profile=mcp-app"]
        })
      )
    else
      response
    end
  end

  defp decorate(%{"result" => %{"contents" => contents}} = response, _request, _conn) do
    put_in(response, ["result", "contents"], Enum.map(contents, &resource_metadata/1))
  end

  defp decorate(%{"result" => %{"resources" => resources}} = response, _request, _conn) do
    put_in(response, ["result", "resources"], Enum.map(resources, &resource_metadata/1))
  end

  defp decorate(
         %{"result" => %{"isError" => false}} = response,
         %{"method" => "tools/call", "params" => %{"name" => name} = params},
         conn
       ) do
    response = update_in(response, ["result"], &Privacy.result/1)

    case Widgets.for_tool(name) do
      nil ->
        response

      app ->
        arguments = params["arguments"] || %{}

        update_in(response, ["result", "_meta"], fn meta ->
          Map.put(meta || %{}, "firmowid/app", Runtime.mount_metadata(conn, app, arguments))
        end)
    end
  end

  defp decorate(response, _request, _conn), do: response

  # AshAi has no serverInfo icons. Initialize-era results carry serverInfo in the result,
  # 2026-07-28 results in `_meta`; clients that render icons get the app favicon.
  defp put_server_icons(responses) when is_list(responses), do: Enum.map(responses, &put_server_icons/1)

  defp put_server_icons(%{"result" => %{"serverInfo" => _info}} = response),
    do: put_in(response, ["result", "serverInfo", "icons"], server_icons())

  defp put_server_icons(%{"result" => %{"_meta" => %{"io.modelcontextprotocol/serverInfo" => _info}}} = response),
    do: put_in(response, ["result", "_meta", "io.modelcontextprotocol/serverInfo", "icons"], server_icons())

  defp put_server_icons(response), do: response

  defp server_icons do
    [
      %{
        "src" => FirmowidMcp.endpoint().url() <> "/images/favicon.png",
        "mimeType" => "image/png",
        "sizes" => ["601x601"]
      }
    ]
  end

  defp tool_metadata(%{"name" => name} = tool) do
    tool =
      tool
      |> Map.new(fn
        {key, schema} when key in ["inputSchema", "outputSchema"] ->
          {key, Privacy.schema(schema, key == "inputSchema")}

        pair ->
          pair
      end)
      |> Map.put("securitySchemes", @security_schemes)
      |> update_in(["_meta"], &Map.put(&1 || %{}, "securitySchemes", @security_schemes))

    case Widgets.for_tool(name) do
      nil ->
        tool

      app ->
        uri = Runtime.resource_uri(app)

        tool
        |> put_in(["inputSchema", "properties", "language"], Runtime.language_schema())
        |> update_in(
          ["_meta"],
          &Map.merge(&1, %{"ui" => %{"resourceUri" => uri}, "openai/outputTemplate" => uri})
        )
    end
  end

  defp resource_metadata(resource) do
    if app = Widgets.for_resource(resource["uri"]) do
      metadata = Runtime.resource_metadata(app)
      html = Map.get_lazy(resource, "text", &Runtime.document/0)

      resource
      |> Map.put("uri", Runtime.resource_uri(app, html))
      |> Map.update("_meta", metadata, &Map.merge(&1, metadata))
    else
      resource
    end
  end
end
