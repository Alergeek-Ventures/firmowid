defmodule Firmowid.Ash.Core.SecretsTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Firmowid.Ash.Core.Secrets
  alias FirmowidWeb.Core.Endpoint

  setup do
    previous = Application.fetch_env(:firmowid, :oauth2_resource_url)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:firmowid, :oauth2_resource_url, value)
        :error -> Application.delete_env(:firmowid, :oauth2_resource_url)
      end
    end)
  end

  test "resource defaults to endpoint /mcp when absent or nil" do
    Application.delete_env(:firmowid, :oauth2_resource_url)
    assert {:ok, Endpoint.url() <> "/mcp"} == resource()
    Application.put_env(:firmowid, :oauth2_resource_url, nil)
    assert {:ok, Endpoint.url() <> "/mcp"} == resource()
  end

  test "configured canonical resource is shared by metadata and server resolution" do
    url =
      "https://tunnel-service.gateway.unified-0.internal.api.openai.org/v1/mcp/tunnel_0123456789abcdef0123456789abcdef"

    Application.put_env(:firmowid, :oauth2_resource_url, url)
    assert resource() == {:ok, url}
    assert Firmowid.Oauth2Server.resource_url() == url

    assert AshAuthentication.Oauth2Server.Metadata.protected_resource(Firmowid.Oauth2Server)[
             "resource"
           ] == url

    assert Secrets.secret_for([:issuer_url], Firmowid.Oauth2Server, [], %{}) ==
             {:ok, Endpoint.url()}
  end

  defp resource, do: Secrets.secret_for([:resource_url], Firmowid.Oauth2Server, [], %{})
end
