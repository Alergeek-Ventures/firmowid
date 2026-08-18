defmodule FirmowidWeb.Mcp.Utilities.RewriteLoopbackRedirectUri do
  @moduledoc """
  Rewrites a `localhost` `redirect_uri` to its `127.0.0.1` equivalent
  before it reaches `ash_authentication_oauth2_server`.

  RFC 8252 §7.3's loopback port-wildcard exception (a native/CLI client
  may bind an ephemeral port at authorization time without
  pre-registering it) applies only to IP literals in
  `ash_authentication_oauth2_server` — `localhost` is deliberately
  excluded there, since a hostname's resolution isn't guaranteed to stay
  loopback. In practice several real OAuth clients (Claude Code among
  them) hardcode `localhost` and never fall back to the IP literal, even
  when their own client metadata advertises support for both — so
  strict enforcement just breaks them. We rewrite the host here instead
  of loosening the check in the dependency, accepting the same
  theoretical, local-machine-only risk that the IP-literal exception
  already accepts.

  Must run after `Plug.Parsers` (see `FirmowidWeb.Core.Endpoint`) so
  `conn.params` / `conn.query_params` / `conn.body_params` are already
  populated — both `/oauth/authorize` (query) and `/oauth/token` (body)
  carry `redirect_uri` this way.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> rewrite(:params)
    |> rewrite(:query_params)
    |> rewrite(:body_params)
  end

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
