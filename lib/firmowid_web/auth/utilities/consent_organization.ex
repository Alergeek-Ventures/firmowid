defmodule FirmowidWeb.Auth.Utilities.ConsentOrganization do
  @moduledoc """
  Binds the MCP consent step to an organization of the signed-in account.

  The OAuth server stores the consent and issues the authorization code for the
  conn's Ash tenant, so this plug sets it before the consent router. The GET
  screen uses the organization selected in the session (an earlier consent for it
  issues the code without the screen) and offers the account's usable
  organizations; an approving POST must name one of them in `organization_id`.
  Install after the browser pipeline; only `/oauth/authorize` is inspected.

  An account that is not ready for the consent yet is led through the setup
  first and comes back to it (see `PendingAuthorization`): an account without a
  company creates or joins one, and with the setup wizard (the `inbox` flag) an
  admin finishes the company's setup. Signed out, the OAuth server sends the
  person to sign in or sign up; the client is remembered so the pages can name it.
  """

  @behaviour Plug

  import Ash.PlugHelpers, only: [get_actor: 1, set_tenant: 2]
  import Phoenix.Controller, only: [current_path: 1, redirect: 2]

  import Plug.Conn,
    only: [fetch_query_params: 1, get_session: 2, halt: 1, register_before_send: 2]

  alias AshAuthentication.Oauth2Server.Authorize
  alias AshAuthentication.Phoenix.Oauth2Server.Errors
  alias Firmowid.Core
  alias Firmowid.Core.User
  alias FirmowidWeb.Auth.Components.McpConsent
  alias FirmowidWeb.Auth.Utilities.PendingAuthorization
  alias FirmowidWeb.Infrastructure.Flags
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation

  @doc "Accepts the pipeline's keyword options without changing them."
  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc "Sets the consent's organization as the tenant of a signed-in account's authorization request."
  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case Enum.map(conn.path_info, &URI.decode/1) do
      ["oauth", "authorize"] -> authorize(conn, get_actor(conn))
      _other -> conn
    end
  end

  defp authorize(%{method: "GET"} = conn, nil) do
    case client_name(conn) do
      {:ok, client} -> PendingAuthorization.put(conn, client, nil)
      :invalid -> conn
    end
  end

  defp authorize(conn, nil), do: conn

  defp authorize(%{method: "GET"} = conn, %User{} = user) do
    members = Core.list_usable_members(user)

    selected =
      Core.select_member(user, members, get_session(conn, UserAuth.organization_session_key()))

    case setup_path(user, selected) do
      nil -> consent(conn, members, selected.member)
      path -> continue_after_setup(conn, path)
    end
  end

  defp authorize(conn, %User{} = user), do: approve(conn, Core.list_usable_members(user))

  defp setup_path(user, %User{member: nil}) do
    if is_nil(Core.load_member(user).member), do: OrganizationNavigation.onboarding_path()
  end

  defp setup_path(_user, %User{member: member} = selected) do
    if UserAuth.first_steps_pending?(selected, member.organization) and
         Flags.flag_enabled?(:inbox, %{feature_flags: Flags.evaluate_for_user(selected)}),
       do: OrganizationNavigation.setup_path()
  end

  defp continue_after_setup(conn, setup_path) do
    case client_name(conn) do
      {:ok, client} ->
        conn
        |> PendingAuthorization.put(client, current_path(conn))
        |> redirect(to: setup_path)
        |> halt()

      :invalid ->
        conn
    end
  end

  # Only a valid request is remembered; the OAuth server answers an invalid one itself.
  defp client_name(conn) do
    case Authorize.validate_request(Firmowid.Oauth2Server, fetch_query_params(conn).query_params) do
      {:ok, %{client: client}} -> {:ok, client.client_name}
      _invalid -> :invalid
    end
  end

  defp consent(conn, members, selected) do
    McpConsent.put_organizations(Enum.map(members, & &1.organization), selected)

    # An earlier consent issues the code without rendering the screen; the
    # connection process may serve further requests.
    conn =
      register_before_send(conn, fn conn ->
        McpConsent.delete_organizations()
        conn
      end)

    conn = PendingAuthorization.delete(conn)

    case selected do
      nil -> conn
      member -> set_tenant(conn, member.organization_id)
    end
  end

  defp approve(%{method: "POST", params: %{"action" => "approve"} = params} = conn, members) do
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

  defp approve(conn, _members), do: conn
end
