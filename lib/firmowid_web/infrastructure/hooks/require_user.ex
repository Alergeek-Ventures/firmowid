defmodule FirmowidWeb.Infrastructure.Hooks.RequireUser do
  @moduledoc """
  LiveView on_mount hook. Requires an authenticated user, with or without an organization.

  Used during onboarding, where the user creates or joins an organization, also
  next to the ones they already belong to. Loads the member selected in the
  session (`nil` for a user without one) and, with one, its organization, the
  organizations to switch between and the Ash scope (see `RequireOrganization`).
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  import Phoenix.Component
  import Phoenix.LiveView

  alias FirmowidWeb.Infrastructure.UserAuth

  def on_mount(:default, _params, session, socket) do
    case socket.assigns[:current_user] &&
           UserAuth.load_member(socket.assigns.current_user, session) do
      nil ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, gettext("You must log in."))
         |> redirect(to: ~p"/zaloguj")}

      {%{member: nil} = user, _organizations} ->
        {:cont,
         socket
         |> assign(:current_user, user)
         |> attach_impersonation_hooks()}

      {user, organizations} ->
        {user, org, scope} = UserAuth.load_scope_and_avatars(user)

        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_org, org)
         |> assign(:organizations, organizations)
         |> assign(:ash_scope, scope)
         |> attach_impersonation_hooks()}
    end
  end

  defp attach_impersonation_hooks(socket) do
    socket
    |> UserAuth.maybe_attach_impersonation_hook(
      :user_impersonation_access,
      :handle_event,
      fn _event, _params, socket -> ensure_impersonation_access(socket) end
    )
    |> UserAuth.maybe_attach_impersonation_hook(
      :user_impersonation_access,
      :handle_params,
      fn _params, _uri, socket -> ensure_impersonation_access(socket) end
    )
  end

  defp ensure_impersonation_access(socket) do
    if UserAuth.impersonation_valid?(socket.assigns.current_user) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/zaloguj")}
    end
  end
end
