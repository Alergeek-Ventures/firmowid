defmodule FirmowidWeb.Mcp.Utilities.PublicClientAuthentication do
  @moduledoc """
  Enforces the OAuth token endpoint's public-client-only authentication policy.

  Install in `:oauth_api` after body parsing and before protocol routing. Only
  the routed `/oauth/token` path is inspected. Client secrets, assertions and
  HTTP Basic authentication are rejected rather than ignored; PKCE, grants,
  tokens and scopes remain the official OAuth server's responsibility.
  """

  @behaviour Plug

  import Plug.Conn

  @forbidden_params ~w(client_assertion client_assertion_type client_secret)

  @doc "Accepts the pipeline's keyword options without changing them."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Rejects unsupported authentication on token requests only."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case Enum.map(conn.path_info, &URI.decode/1) do
      ["oauth", "token"] -> enforce_public_client(conn)
      _path -> conn
    end
  end

  defp enforce_public_client(conn) do
    conn = fetch_query_params(conn)

    if forbidden_params?(conn.body_params) or forbidden_params?(conn.query_params) or
         basic_authentication?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> send_resp(
        400,
        Jason.encode!(%{
          error: "invalid_client",
          error_description: "Unsupported client authentication method; only none is supported."
        })
      )
      |> halt()
    else
      conn
    end
  end

  defp forbidden_params?(params), do: Enum.any?(@forbidden_params, &Map.has_key?(params, &1))

  defp basic_authentication?(conn) do
    conn
    |> get_req_header("authorization")
    |> Enum.any?(fn header ->
      case String.split(header, ~r/\s+/, parts: 2, trim: true) do
        [scheme | _rest] -> String.downcase(scheme) == "basic"
        [] -> false
      end
    end)
  end
end
