defmodule FirmowidWeb.Infrastructure.Controllers.AgentDiscovery do
  @moduledoc """
  Serves public discovery documents that let AI agents find the Firmowid MCP
  server: the AI Catalog, the MCP Server Card, the RFC 9727 API catalog, the
  Agent Skills index and the Markdown version of the home page.
  """
  use FirmowidWeb, :controller

  alias AshAi.Mcp.Server
  alias FirmowidWeb.Core.Endpoint

  @server_card_type "application/mcp-server-card+json"

  @skill_name "firmowid-mcp"

  @doc "Returns the Link header value advertising the discovery documents."
  @spec link_header() :: String.t()
  def link_header, do: ~s(</.well-known/api-catalog>; rel="api-catalog", </.well-known/ai-catalog.json>; rel="ai-catalog")

  @doc "Returns the AI Catalog listing the MCP Server Card."
  @spec ai_catalog(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ai_catalog(conn, _params) do
    host = URI.parse(Endpoint.url()).host

    send_document(conn, "application/ai-catalog+json", %{
      "specVersion" => "1.0",
      "host" => %{"displayName" => "Firmowid", "identifier" => "did:web:#{host}"},
      "entries" => [
        %{
          "identifier" => "urn:air:#{host}:mcp:firmowid",
          "displayName" => "Firmowid",
          "type" => @server_card_type,
          "url" => server_card_url(),
          "representativeQueries" => [
            "wystaw fakturę dla klienta i wyślij ją do KSeF",
            "pokaż nieopłacone faktury sprzedażowe",
            "dopasuj przelewy z banku do faktur kosztowych",
            "zarejestruj czas pracy nad projektem"
          ]
        }
      ]
    })
  end

  @doc "Returns the MCP Server Card describing the remote MCP endpoint."
  @spec server_card(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def server_card(conn, _params) do
    send_document(conn, @server_card_type, %{
      "$schema" => "https://static.modelcontextprotocol.io/schemas/v1/server-card.schema.json",
      "name" => "pl.firmowid/firmowid",
      "version" => Server.get_server_version(otp_app: :firmowid),
      "title" => "Firmowid",
      "description" =>
        "Faktury i KSeF, dopasowanie transakcji bankowych, ewidencja czasu pracy i urlopy dla polskich firm.",
      "websiteUrl" => Endpoint.url(),
      "remotes" => [
        %{
          "type" => "streamable-http",
          "url" => Firmowid.Oauth2Server.resource_url(),
          "supportedProtocolVersions" => Server.supported_protocol_versions()
        }
      ]
    })
  end

  @doc "Answers CORS preflight requests for the Server Card."
  @spec preflight(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def preflight(conn, _params), do: conn |> put_cors_headers() |> send_resp(204, "")

  @doc "Returns the Agent Skills discovery index (v0.2.0)."
  @spec agent_skills(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def agent_skills(conn, _params) do
    skill = read_skill()
    # The index description must match the SKILL.md frontmatter.
    [description] = Regex.run(~r/^description: (.+)$/m, skill, capture: :all_but_first)

    send_document(conn, "application/json", %{
      "$schema" => "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
      "skills" => [
        %{
          "name" => @skill_name,
          "type" => "skill-md",
          "description" => description,
          "url" => "/.well-known/agent-skills/#{@skill_name}/SKILL.md",
          "digest" => "sha256:" <> Base.encode16(:crypto.hash(:sha256, skill), case: :lower)
        }
      ]
    })
  end

  @doc "Returns the SKILL.md listed in the Agent Skills index."
  @spec agent_skill(Plug.Conn.t(), map()) :: Plug.Conn.t()
  # sobelow_skip ["XSS.SendResp"]
  # The body is the fixed SKILL.md from application priv, never request input.
  def agent_skill(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, read_skill())
  end

  defp read_skill, do: read_priv("priv/agent_skills/#{@skill_name}/SKILL.md")

  @doc "Returns `llms.txt` as the Markdown representation of the home page."
  @spec markdown_home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  # sobelow_skip ["XSS.SendResp"]
  # The body is the fixed llms.txt from application priv, never request input.
  def markdown_home(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("vary", "accept")
    |> send_resp(200, read_priv("priv/static/llms.txt"))
  end

  @doc "Returns the RFC 9727 API catalog for the MCP endpoint."
  @spec api_catalog(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def api_catalog(conn, _params) do
    mcp_url = Firmowid.Oauth2Server.resource_url()

    conn
    |> put_resp_header("link", ~s(</.well-known/api-catalog>; rel="api-catalog"))
    |> send_document(
      ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727"),
      %{
        "linkset" => [
          %{
            "anchor" => mcp_url,
            "service-desc" => [%{"href" => server_card_url(), "type" => @server_card_type}],
            "service-doc" => [%{"href" => "#{Endpoint.url()}/#asystent", "type" => "text/html"}],
            "service-meta" => [
              %{"href" => protected_resource_metadata_url(mcp_url), "type" => "application/json"}
            ],
            "status" => [%{"href" => "#{Endpoint.url()}/health", "type" => "application/json"}]
          }
        ]
      }
    )
  end

  defp server_card_url, do: "#{Endpoint.url()}/mcp/server-card"

  # RFC 9728 §3.1 inserts the well-known segment between the host and the resource path.
  defp protected_resource_metadata_url(resource_url) do
    %URI{path: path} = uri = URI.parse(resource_url)
    URI.to_string(%{uri | path: "/.well-known/oauth-protected-resource#{path}"})
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Callers pass fixed paths in application priv, never request input.
  defp read_priv(path), do: :firmowid |> Application.app_dir(path) |> File.read!()

  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  # Content types are module literals and the JSON body holds only configured
  # URLs and fixed metadata, never request input.
  defp send_document(conn, content_type, document) do
    conn
    |> put_resp_content_type(content_type, nil)
    |> put_cors_headers()
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, Jason.encode!(document))
  end

  # The public, read-only header set required for hosted Server Cards.
  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET")
    |> put_resp_header("access-control-allow-headers", "Content-Type, If-None-Match")
    |> put_resp_header("access-control-expose-headers", "ETag")
  end
end
