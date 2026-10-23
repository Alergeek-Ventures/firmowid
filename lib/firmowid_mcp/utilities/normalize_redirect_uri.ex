defmodule FirmowidMcp.Utilities.NormalizeRedirectUri do
  @moduledoc """
  Validates OAuth redirect URIs and normalizes `localhost` to `127.0.0.1` for
  ephemeral loopback ports. Rejects ambiguous authorities before the library's
  loopback comparison, which ignores userinfo and fragments.

  Runs after `Plug.Parsers` to normalize both authorization queries and token bodies.
  """

  @behaviour Plug

  alias AshAuthentication.Phoenix.Oauth2Server.Errors

  @parameter_keys [:params, :query_params, :body_params]
  @loopback_hosts ["localhost", "127.0.0.1", "::1"]

  @doc false
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Rejects invalid redirect URIs and normalizes localhost in parsed parameters."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if Enum.any?(@parameter_keys, &invalid_redirect?(Map.get(conn, &1))) do
      Errors.send_oauth_error(conn, 400, "invalid_request")
    else
      Enum.reduce(@parameter_keys, conn, &rewrite(&2, &1))
    end
  end

  defp invalid_redirect?(%{"redirect_uri" => uri}) when is_binary(uri) and uri != "" do
    uri =~ ~r/[\\\x00-\x20\x7F]/ or
      case URI.new(uri) do
        {:ok, %URI{scheme: "https", host: host, userinfo: nil, fragment: nil}}
        when is_binary(host) and host != "" ->
          false

        {:ok, %URI{scheme: "http", host: host, userinfo: nil, fragment: nil}}
        when host in @loopback_hosts ->
          false

        _ ->
          true
      end
  end

  defp invalid_redirect?(_params), do: false

  defp rewrite(conn, key) do
    with %{"redirect_uri" => uri} = params when is_binary(uri) <- Map.get(conn, key),
         %URI{host: "localhost"} = parsed <- URI.parse(uri) do
      rewritten = URI.to_string(%{parsed | host: "127.0.0.1"})
      Map.put(conn, key, Map.put(params, "redirect_uri", rewritten))
    else
      _ -> conn
    end
  end
end
