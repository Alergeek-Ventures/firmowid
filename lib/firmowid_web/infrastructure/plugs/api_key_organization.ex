defmodule FirmowidWeb.Infrastructure.Plugs.ApiKeyOrganization do
  @moduledoc """
  After `AshAuthentication.Strategy.ApiKey.Plug`, works in the organization of the key:
  sets it as the Ash tenant and loads the actor's member there.

  The key's account must still have a usable member in that organization (see
  `Firmowid.Core.load_member/2`), so a key of an organization without a billing plan
  is rejected rather than used in another organization of the account. The member must
  also still be an admin: a key acts as the admin who created it, so it stops working
  while that person has a lower role.
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [get_actor: 1, set_actor: 2, set_tenant: 2]
  import Plug.Conn

  alias Firmowid.Core
  alias Firmowid.Core.ApiKey
  alias Firmowid.Core.User

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with %User{__metadata__: %{api_key: %ApiKey{organization_id: organization_id}}} = actor <-
           get_actor(conn),
         %User{member: %{organization_id: ^organization_id, role: :admin}} = actor <-
           Core.load_member(actor, organization_id) do
      conn
      |> set_actor(actor)
      |> set_tenant(organization_id)
      |> assign(:current_user, actor)
    else
      _actor -> unauthorized(conn, :organization_required)
    end
  end

  @doc """
  Rejects the request with a JSON 401. It is also the `on_error` of the API key plug,
  which calls it for a missing or invalid key.
  """
  @spec unauthorized(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def unauthorized(conn, _error) do
    body = Jason.encode!(%{error: "unauthorized", message: "A valid API key is required"})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
