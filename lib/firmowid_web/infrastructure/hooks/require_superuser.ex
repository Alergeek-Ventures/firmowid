defmodule FirmowidWeb.Infrastructure.Hooks.RequireSuperuser do
  @moduledoc """
  LiveView on_mount hook. Requires superuser role, on mount and again before
  every event, so a role revoked while an admin page is open stops its actions.

  Events of a LiveComponent do not pass through the view's hooks: an admin
  component that acts on data needs its own check.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  import Phoenix.LiveView

  alias Firmowid.Core
  alias FirmowidWeb.Infrastructure.UserAuth

  @doc false
  def on_mount(:default, _params, _session, %{assigns: %{current_user: current_user}} = socket) do
    if UserAuth.superuser?(current_user) do
      {:cont, attach_hook(socket, :superuser_access, :handle_event, &ensure_superuser/3)}
    else
      {:halt, deny(socket)}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    {:halt,
     socket
     |> LiveToast.put_toast(:notice, gettext("You must log in."))
     |> redirect(to: ~p"/zaloguj")}
  end

  defp ensure_superuser(_event, _params, socket) do
    user = socket.assigns.current_user

    case Core.get_user(user.id, actor: user) do
      {:ok, %{system_role: :superuser}} -> {:cont, socket}
      _revoked -> {:halt, deny(socket)}
    end
  end

  defp deny(socket) do
    socket
    |> LiveToast.put_toast(:error, gettext("You do not have access to this section."))
    |> redirect(to: ~p"/")
  end
end
