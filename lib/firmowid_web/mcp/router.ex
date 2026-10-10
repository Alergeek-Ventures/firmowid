defmodule FirmowidWeb.Mcp.Router do
  @moduledoc "Native AshAi MCP transport with feature-owned, optional LiveView presentations."
  @behaviour Plug

  import Plug.Conn

  alias AshAi.Mcp.Router, as: Transport
  alias FirmowidWeb.Mcp.Apps
  alias FirmowidWeb.Mcp.Runtime

  @security_schemes [%{"type" => "oauth2", "scopes" => ["mcp"]}]

  @impl true
  @doc "Initializes the explicit tool and resource allowlists."
  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts |> Keyword.put(:otp_app, :firmowid) |> Transport.init()
  end

  @impl true
  @doc "Preserves native protocol validation/envelopes and decorates successful presentations."
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> register_before_send(&decorate_response/1)
    |> Transport.call(opts)
  end

  defp decorate_response(conn) do
    case Jason.decode(conn.resp_body || "") do
      {:ok, response} ->
        response = decorate(response, conn.body_params, conn)
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
         %{"result" => %{"isError" => false, "structuredContent" => data}} = response,
         %{"method" => "tools/call", "params" => %{"name" => name} = params},
         conn
       ) do
    case Apps.for_tool(name) do
      nil ->
        response

      app ->
        data = app.present_result(data)
        arguments = params["arguments"] || %{}

        response
        |> put_in(["result", "structuredContent"], data)
        |> put_in(["result", "content"], [%{"type" => "text", "text" => Jason.encode!(data)}])
        |> update_in(["result", "_meta"], fn meta ->
          Map.put(meta || %{}, "firmowid/app", Runtime.mount_metadata(conn, app, arguments))
        end)
    end
  end

  defp decorate(response, _request, _conn), do: response

  defp tool_metadata(tool) do
    case Apps.for_tool(tool["name"]) do
      nil ->
        tool

      app ->
        tool
        |> Map.put("outputSchema", app.output_schema())
        |> Map.put("securitySchemes", @security_schemes)
        |> Map.put("annotations", app.annotations())
        |> update_in(["_meta"], fn meta ->
          Map.merge(meta || %{}, %{
            "securitySchemes" => @security_schemes,
            "ui" => %{"resourceUri" => app.resource_uri()},
            "openai/outputTemplate" => app.resource_uri()
          })
        end)
    end
  end

  defp resource_metadata(resource) do
    if Apps.for_resource(resource["uri"]) do
      Map.update(
        resource,
        "_meta",
        Runtime.resource_metadata(),
        &Map.merge(&1, Runtime.resource_metadata())
      )
    else
      resource
    end
  end
end
