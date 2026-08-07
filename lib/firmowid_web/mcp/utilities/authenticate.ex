defmodule FirmowidWeb.Mcp.Utilities.Authenticate do
  @moduledoc """
  After Oauth2Server BearerPlug, require an organization and set the Ash tenant.
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [get_actor: 1, set_tenant: 2]
  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_actor(conn) do
      %{organization_id: org_id} when not is_nil(org_id) ->
        set_tenant(conn, org_id)

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
