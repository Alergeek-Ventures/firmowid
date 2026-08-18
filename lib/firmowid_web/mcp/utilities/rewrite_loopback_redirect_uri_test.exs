defmodule FirmowidWeb.Mcp.Utilities.RewriteLoopbackRedirectUriTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidWeb.Mcp.Utilities.RewriteLoopbackRedirectUri

  test "rewrites localhost redirect URIs from authorization query parameters" do
    redirect_uri = "http://localhost:54321/callback"

    conn =
      :get
      |> Plug.Test.conn("/oauth/authorize?redirect_uri=#{URI.encode_www_form(redirect_uri)}")
      |> Plug.Conn.fetch_query_params()
      |> RewriteLoopbackRedirectUri.call([])

    assert conn.params["redirect_uri"] == "http://127.0.0.1:54321/callback"
    assert conn.query_params["redirect_uri"] == "http://127.0.0.1:54321/callback"
  end

  test "rewrites localhost redirect URIs from token form parameters" do
    conn =
      :post
      |> Plug.Test.conn("/oauth/token", %{"redirect_uri" => "http://localhost:54321/callback"})
      |> RewriteLoopbackRedirectUri.call([])

    assert conn.params["redirect_uri"] == "http://127.0.0.1:54321/callback"
    assert conn.body_params["redirect_uri"] == "http://127.0.0.1:54321/callback"
  end

  test "leaves non-loopback redirect URIs unchanged" do
    redirect_uri = "https://example.com/callback"

    conn =
      :get
      |> Plug.Test.conn("/oauth/authorize?redirect_uri=#{URI.encode_www_form(redirect_uri)}")
      |> Plug.Conn.fetch_query_params()
      |> RewriteLoopbackRedirectUri.call([])

    assert conn.params["redirect_uri"] == redirect_uri
    assert conn.query_params["redirect_uri"] == redirect_uri
  end
end
