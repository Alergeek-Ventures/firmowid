defmodule FirmowidWeb.Infrastructure.Hooks.RequireUser do
  @moduledoc """
  LiveView on_mount hook. Requires an authenticated user, with or without an organization.

  Used during onboarding, where the user creates or joins an organization, also
  next to the ones they already belong to. Loads the member selected in the
  session (`nil` for a user without one) and, with one, what the navbar shows
  (see `RequireOrganization`).
  """

  use FirmowidWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias FirmowidWeb.Infrastructure.UserAuth

  def on_mount(:default, _params, session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, "Musisz się zalogować.")
         |> redirect(to: ~p"/zaloguj")}

      user ->
        case UserAuth.load_member(user, session) do
          {%{member: nil} = user, _organizations} ->
            {:cont, assign(socket, :current_user, user)}

          {user, organizations} ->
            {user, org, scope} = UserAuth.load_scope_and_avatars(user)

            {:cont,
             socket
             |> assign(:current_user, user)
             |> assign(:current_org, org)
             |> assign(:organizations, organizations)
             |> assign(:ash_scope, scope)}
        end
    end
  end
end
