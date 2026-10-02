defmodule Firmowid.Config.ChatgptOauthResourceTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Config.ChatgptOauthResource

  @host "tunnel-service.gateway.unified-0.internal.api.openai.org"
  @path "/v1/mcp/tunnel_0123456789abcdef0123456789abcdef"
  @url "https://#{@host}#{@path}"

  test "absence preserves default and valid URLs retain their exact value" do
    assert ChatgptOauthResource.validate!(nil) == nil
    assert ChatgptOauthResource.validate!(@url) == @url

    assert ChatgptOauthResource.validate!("https://#{@host}:443#{@path}") ==
             "https://#{@host}:443#{@path}"
  end

  test "rejects malformed URLs without aliases or normalization" do
    for url <- [
          "",
          " #{@url}",
          @url <> "\n",
          String.replace(@url, "https:", "http:"),
          String.replace(@url, "https:", "HTTPS:"),
          "https://other.example#{@path}",
          "https://user@#{@host}#{@path}",
          "https://#{@host}:444#{@path}",
          "https://#{@host}:0443#{@path}",
          @url <> "?",
          @url <> "#",
          @url <> "/",
          String.upcase(@url),
          String.replace(@url, "tunnel_", "tunnel_%"),
          @url <> "0",
          "https://#{@host}/mcp"
        ] do
      assert_raise ArgumentError, fn -> ChatgptOauthResource.validate!(url) end
    end
  end
end
