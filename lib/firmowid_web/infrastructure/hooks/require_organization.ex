defmodule FirmowidWeb.Infrastructure.Hooks.RequireOrganization do
  @moduledoc """
  LiveView on_mount hook. Requires authenticated user with an organization.

  After ash_authentication_live_session populates `current_user`, this hook:
  1. Redirects to /zaloguj if no user
  2. Loads the member of the organization selected in the session (see
     `UserAuth.load_member/2`); redirects to /organizacja if there is none
  3. Loads avatar on user and organization via shared `UserAuth.load_scope_and_avatars/1`
  4. Assigns current_user, current_org, organizations (to switch between), ash_scope
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  import Phoenix.Component
  import Phoenix.LiveView

  alias Firmowid.Core
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation
  alias Phoenix.LiveView.Socket

  def on_mount(:default, _params, session, socket) do
    case socket.assigns[:current_user] &&
           UserAuth.load_member(socket.assigns.current_user, session) do
      nil ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, gettext("You must log in."))
         |> redirect(to: ~p"/zaloguj")}

      {%{member: nil}, _organizations} ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, gettext("To continue, assign yourself an organization."))
         |> redirect(to: OrganizationNavigation.onboarding_path())}

      {user, organizations} ->
        {user, org, scope} = UserAuth.load_scope_and_avatars(user)

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_org, org)
         |> assign(:organizations, organizations)
         |> assign(:ash_scope, scope)
         |> attach_access_hook(:ash_scope)}
    end
  end

  @doc "Checks the current organization and role before LiveView or LiveComponent events."
  @spec attach_access_hook(Socket.t(), atom()) :: Socket.t()
  def attach_access_hook(socket, scope_assign) do
    attach_hook(socket, :organization_access, :handle_event, fn _event, _params, socket ->
      ensure_organization_access(socket, Map.fetch!(socket.assigns, scope_assign))
    end)
  end

  @doc "Checks organization access before upload progress callbacks, which bypass event hooks."
  @spec guard_upload_progress(function(), atom()) :: function()
  def guard_upload_progress(callback, scope_assign) do
    fn name, entry, socket ->
      case ensure_organization_access(socket, Map.fetch!(socket.assigns, scope_assign)) do
        {:cont, socket} -> callback.(name, entry, socket)
        {:halt, socket} -> {:noreply, socket}
      end
    end
  end

  defp ensure_organization_access(socket, %{actor: user, tenant: tenant}) do
    %{id: member_id, role: role} = user.member

    case Core.load_member(user, tenant) do
      %{member: %{id: ^member_id, role: ^role, organization_id: ^tenant}} ->
        {:cont, socket}

      _ ->
        {:halt, redirect(socket, to: OrganizationNavigation.onboarding_path())}
    end
  end
end
