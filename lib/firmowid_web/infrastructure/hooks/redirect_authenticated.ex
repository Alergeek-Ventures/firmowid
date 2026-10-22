defmodule FirmowidWeb.Infrastructure.Hooks.RedirectAuthenticated do
  @moduledoc """
  LiveView on_mount hook. Redirects authenticated users away from guest pages.

  Used on login/register pages to prevent logged-in users from seeing them.
  """

  use FirmowidWeb, :verified_routes

  import Phoenix.LiveView

  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation

  def on_mount(:default, _params, session, socket) do
    case socket.assigns[:current_user] &&
           UserAuth.load_member(socket.assigns.current_user, session) do
      nil ->
        {:cont, socket}

      {%{member: nil}, _organizations} ->
        {:halt, redirect(socket, to: OrganizationNavigation.onboarding_path())}

      {user, _organizations} ->
        {:halt, redirect(socket, to: UserAuth.signed_in_path_for_user(user, user.member.organization_id))}
    end
  end
end
