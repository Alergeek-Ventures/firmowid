defmodule FirmowidWeb.Infrastructure.Hooks.RedirectAuthenticated do
  @moduledoc """
  LiveView on_mount hook. Redirects authenticated users away from guest pages.

  Used on login/register pages to prevent logged-in users from seeing them.
  """

  use FirmowidWeb, :verified_routes

  import Phoenix.LiveView

  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:cont, socket}

      %{organization_id: nil} ->
        {:halt, redirect(socket, to: OrganizationNavigation.onboarding_path())}

      user ->
        {:halt, redirect(socket, to: UserAuth.signed_in_path_for_user(user))}
    end
  end
end
