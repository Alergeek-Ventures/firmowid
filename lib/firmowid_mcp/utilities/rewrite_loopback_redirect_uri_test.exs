defmodule FirmowidMcp.Utilities.RewriteLoopbackRedirectUriTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidMcp.Utilities.RewriteLoopbackRedirectUri

  test "never rewrites incoming resource parameters" do
    params = %{
      "resource" => "https://arbitrary.example/mcp",
      "redirect_uri" => "http://localhost:54321/callback"
    }

    conn = :post |> Plug.Test.conn("/oauth/token", params) |> RewriteLoopbackRedirectUri.call([])
    assert conn.params["resource"] == params["resource"]
    assert conn.body_params["resource"] == params["resource"]
  end

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

  test "rejects ambiguous redirect URIs in query and token form parameters" do
    for uri <- [
          "http://attacker.invalid\\@127.0.0.1/callback",
          "http://user@localhost/callback",
          "http://127.0.0.1/callback#fragment",
          "http://127.0.0.1/\tcallback"
        ],
        method <- [:get, :post] do
      conn =
        case method do
          :get ->
            :get
            |> Plug.Test.conn("/oauth/authorize?" <> URI.encode_query(%{"redirect_uri" => uri}))
            |> Plug.Conn.fetch_query_params()

          :post ->
            Plug.Test.conn(:post, "/oauth/token", %{"redirect_uri" => uri})
        end

      conn = RewriteLoopbackRedirectUri.call(conn, [])
      assert conn.status == 400
      assert conn.halted
      assert Jason.decode!(conn.resp_body) == %{"error" => "invalid_request"}
    end
  end
end
