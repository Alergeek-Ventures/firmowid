defmodule FirmowidMcp.Utilities.Authenticate do
  @moduledoc """
  After Oauth2Server BearerPlug, require an organization, set the Ash tenant and
  load the actor's member.

  An account with several organizations works in its default one: the most
  recently updated usable membership (see `Firmowid.Ash.Core.load_member/2` without a selection).
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [get_actor: 1, set_actor: 2, set_tenant: 2]
  import Plug.Conn

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_actor(conn) do
      %User{} = actor ->
        case Core.load_member(actor) do
          %{member: nil} ->
            unauthorized(conn, "Organization required")

          %{member: member} = actor ->
            conn
            |> set_actor(actor)
            |> set_tenant(member.organization_id)
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
