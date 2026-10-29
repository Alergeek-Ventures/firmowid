defmodule FirmowidWeb.Infrastructure.Hooks.RequireSuperuser do
  @moduledoc """
  LiveView on_mount hook. Requires superuser role.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  import Phoenix.LiveView

  alias FirmowidWeb.Infrastructure.UserAuth

  @doc false
  def on_mount(:default, _params, _session, %{assigns: %{current_user: current_user}} = socket) do
    if UserAuth.superuser?(current_user) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> LiveToast.put_toast(:error, gettext("You do not have access to this section."))
       |> redirect(to: ~p"/")}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    {:halt,
     socket
     |> LiveToast.put_toast(:notice, gettext("You must log in."))
     |> redirect(to: ~p"/zaloguj")}
  end
end
