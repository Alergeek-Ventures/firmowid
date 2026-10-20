defmodule FirmowidMcp.Utilities.Authenticate do
  @moduledoc """
  After Oauth2Server BearerPlug, require an organization, set the Ash tenant and
  load the actor's member.
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [get_actor: 1, set_actor: 2, set_tenant: 2]
  import Plug.Conn

  alias Firmowid.Ash.Core

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_actor(conn) do
      %{organization_id: org_id} = actor when not is_nil(org_id) ->
        conn
        |> set_actor(Core.load_member(actor, org_id))
        |> set_tenant(org_id)

      %{organization_id: nil} ->
        unauthorized(conn, "Organization required")

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
