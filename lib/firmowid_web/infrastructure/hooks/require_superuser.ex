defmodule FirmowidWeb.Infrastructure.Hooks.RequireSuperuser do
  @moduledoc """
  LiveView on_mount hook. Requires superuser role, on mount and again before
  every event and every navigation, so a role revoked while an admin page is
  open stops its actions and does not let it load another organization.

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
      {:cont,
       socket
       |> attach_hook(:superuser_access, :handle_event, &ensure_superuser_on_event/3)
       |> attach_hook(:superuser_access, :handle_params, &ensure_superuser_on_params/3)}
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

  defp ensure_superuser_on_event(_event, _params, socket), do: ensure_superuser(socket)

  defp ensure_superuser_on_params(_params, _uri, socket), do: ensure_superuser(socket)

  defp ensure_superuser(socket) do
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
