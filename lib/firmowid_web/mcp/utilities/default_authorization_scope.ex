defmodule FirmowidWeb.Mcp.Utilities.DefaultAuthorizationScope do
  @moduledoc """
  Defaults an omitted OAuth authorization scope to Firmowid's basic MCP scope.

  Only GET `/oauth/authorize` requests are normalized. Explicit scopes, including
  empty or malformed values, remain subject to the OAuth server's validation.
  Consent POSTs retain their server-sealed scope; token requests are untouched.
  """

  @behaviour Plug

  import Plug.Conn, only: [fetch_query_params: 1]

  @doc "Accepts the pipeline's keyword options without changing them."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Adds the basic MCP scope only when the authorization query omits it."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    case Enum.map(conn.path_info, &URI.decode/1) do
      ["oauth", "authorize"] -> default_scope(conn)
      _path -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp default_scope(conn) do
    conn = fetch_query_params(conn)

    if Map.has_key?(conn.query_params, "scope") do
      conn
    else
      %{
        conn
        | query_params: Map.put(conn.query_params, "scope", "mcp"),
          params: Map.put(conn.params, "scope", "mcp")
      }
    end
  end
end
