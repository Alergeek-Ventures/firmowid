defmodule FirmowidMcp.Utilities.Authenticate do
  @moduledoc """
  After Oauth2Server BearerPlug, require an organization, set the Ash tenant and
  load the actor's member.

  The token's `tenant` claim (restored by BearerPlug) is the organization chosen
  on the consent screen: the account works there while it has a usable member
  in it, and is rejected otherwise rather than moved to another organization.
  Tokens issued before the choice existed carry no claim and work in the default
  organization: the most recently updated usable membership (see
  `Firmowid.Core.load_member/2` without a selection).
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [get_actor: 1, get_tenant: 1, set_actor: 2, set_tenant: 2]
  import Plug.Conn

  alias Firmowid.Core
  alias Firmowid.Core.User

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_actor(conn) do
      %User{} = actor ->
        tenant = get_tenant(conn)

        case Core.load_member(actor, tenant) do
          %{member: %{organization_id: organization_id} = member} = actor
          when is_nil(tenant) or organization_id == tenant ->
            conn
            |> set_actor(actor)
            |> set_tenant(member.organization_id)

          _actor ->
            unauthorized(conn, "Organization required")
        end

      _ ->
        unauthorized(conn, "Authentication required")
    end
  end

  defp unauthorized(conn, message) do
    body = Jason.encode!(%{error: "unauthorized", message: message})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
