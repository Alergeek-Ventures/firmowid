defmodule FirmowidMcp.Utilities.RewriteLoopbackRedirectUri do
  @moduledoc """
  Validates redirect URIs and rewrites `localhost` to `127.0.0.1` before
  they reach `ash_authentication_oauth2_server`.

  Rejects userinfo, fragments and ambiguous URL separators before the library's
  loopback port-wildcard comparison. Keeps the existing localhost normalization
  for native/CLI clients using ephemeral callback ports (RFC 8252 §7.3).

  Must run after `Plug.Parsers` (see `FirmowidWeb.Core.Endpoint`) so
  `conn.params` / `conn.query_params` / `conn.body_params` are already
  populated — both `/oauth/authorize` (query) and `/oauth/token` (body)
  carry `redirect_uri` this way.
  """

  @behaviour Plug

  alias AshAuthentication.Phoenix.Oauth2Server.Errors

  @parameter_keys [:params, :query_params, :body_params]
  @loopback_hosts ["localhost", "127.0.0.1", "::1"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Enum.any?(@parameter_keys, &invalid_redirect?(Map.get(conn, &1))) do
      Errors.send_oauth_error(conn, 400, "invalid_request")
    else
      Enum.reduce(@parameter_keys, conn, &rewrite(&2, &1))
    end
  end

  # The library's loopback comparison ignores userinfo and fragments. Reject
  # those and browser URL separators before parsing can normalize the authority.
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
