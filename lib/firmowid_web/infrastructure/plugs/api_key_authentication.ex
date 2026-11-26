defmodule FirmowidWeb.Infrastructure.Plugs.ApiKeyAuthentication do
  @moduledoc """
  Signs a request in with the API key in its `Authorization: Bearer` header and works in the
  key's organization: sets it as the Ash tenant and the key's actor as the Ash actor (see
  `Firmowid.Core.ApiKey`).

  A personal key acts as its `User`, whose member in the key's organization is loaded, and a
  company key as its `ServiceAccount`. A personal key works only while its person can still
  work in that organization (see `Firmowid.Core.load_member/2`), so it is never used in another
  organization of the account. The actor carries the key in its metadata like a key signed in
  by ash_authentication, so `AshAuthentication.Checks.UsingApiKey` recognizes it. Any failure is
  a JSON 401.
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [set_actor: 2, set_tenant: 2]
  import Plug.Conn

  alias Firmowid.Core
  alias Firmowid.Core.ApiKey
  alias Firmowid.Core.User

  # Signing in has no actor yet: the key's secret is what authorizes reading it.
  @auth_context %{private: %{ash_authentication?: true}}

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> api_key] <- get_req_header(conn, "authorization"),
         {:ok, %ApiKey{} = key} <-
           Core.sign_in_with_api_key(String.trim(api_key), context: @auth_context),
         {:ok, actor} <- actor(key) do
      conn
      |> set_actor(Ash.Resource.set_metadata(actor, %{using_api_key?: true, api_key: key}))
      |> set_tenant(key.organization_id)
    else
      _error -> unauthorized(conn)
    end
  end

  defp actor(%ApiKey{service_account_id: id, organization_id: organization_id}) when is_binary(id),
    do: Core.get_service_account(id, context: @auth_context, tenant: organization_id)

  defp actor(%ApiKey{user_id: id, organization_id: organization_id}) do
    with {:ok, user} <- Core.get_user(id, context: @auth_context) do
      case Core.load_member(user, organization_id) do
        %User{member: %{organization_id: ^organization_id}} = user -> {:ok, user}
        _user -> :error
      end
    end
  end

  defp unauthorized(conn) do
    body = Jason.encode!(%{error: "unauthorized", message: "A valid API key is required"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
