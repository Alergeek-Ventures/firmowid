defmodule FirmowidMcp.Utilities.ConsentOrganization do
  @moduledoc """
  Binds the MCP consent step to an organization of the signed-in account.

  The OAuth server stores the consent and issues the authorization code for the
  conn's Ash tenant, so this plug sets it before the consent router. The GET
  screen uses the organization selected in the session (an earlier consent for it
  issues the code without the screen) and offers the account's usable
  organizations; an approving POST must name one of them in `organization_id`.
  Install after the browser pipeline; only `/oauth/authorize` is inspected.
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [get_actor: 1, set_tenant: 2]
  import Plug.Conn, only: [get_session: 2, register_before_send: 2]

  alias AshAuthentication.Phoenix.Oauth2Server.Errors
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias FirmowidWeb.Auth.Components.McpConsent
  alias FirmowidWeb.Infrastructure.UserAuth

  @doc "Accepts the pipeline's keyword options without changing them."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Sets the consent's organization as the tenant of a signed-in account's authorization request."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with ["oauth", "authorize"] <- Enum.map(conn.path_info, &URI.decode/1),
         %User{} = user <- get_actor(conn) do
      authorize(conn, Core.list_usable_members(user), user)
    else
      _ -> conn
    end
  end

  defp authorize(%{method: "GET"} = conn, members, user) do
    selected =
      Core.select_member(user, members, get_session(conn, UserAuth.organization_session_key())).member

    McpConsent.put_organizations(Enum.map(members, & &1.organization), selected)

    # An earlier consent issues the code without rendering the screen; the
    # connection process may serve further requests.
    conn =
      register_before_send(conn, fn conn ->
        McpConsent.delete_organizations()
        conn
      end)

    case selected do
      nil -> conn
      member -> set_tenant(conn, member.organization_id)
    end
  end

  defp authorize(%{method: "POST", params: %{"action" => "approve"} = params} = conn, members, _user) do
    case Enum.find(members, &(&1.organization_id == params["organization_id"])) do
      nil ->
        Errors.send_oauth_error(
          conn,
          400,
          "invalid_request",
          "organization_id is not an organization of the user"
        )

      member ->
        set_tenant(conn, member.organization_id)
    end
  end

  defp authorize(conn, _members, _user), do: conn
end
