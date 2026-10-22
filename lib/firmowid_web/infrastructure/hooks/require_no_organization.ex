defmodule FirmowidWeb.Infrastructure.Hooks.RequireNoOrganization do
  @moduledoc """
  LiveView on_mount hook. Requires authenticated user WITHOUT an organization.

  Used during onboarding when the user needs to create/join an organization.
  """

  use FirmowidWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Firmowid.Ash.Core

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] && Core.load_member(socket.assigns.current_user) do
      nil ->
        {:halt,
         socket
         |> LiveToast.put_toast(:notice, "Musisz się zalogować.")
         |> redirect(to: ~p"/zaloguj")}

      %{member: nil} = user ->
        {:cont, assign(socket, :current_user, user)}

      _user ->
        {:halt, redirect(socket, to: ~p"/")}
    end
  end
end
