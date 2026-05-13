defmodule FirmowidWeb.Infrastructure.Hooks.RequireSuperuser do
  @moduledoc """
  LiveView on_mount hook. Requires superuser role.
  """

  use FirmowidWeb, :verified_routes

  import Phoenix.LiveView

  alias FirmowidWeb.Infrastructure.UserAuth

  @doc false
  def on_mount(:default, _params, _session, %{assigns: %{current_user: current_user}} = socket) do
    if UserAuth.superuser?(current_user) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> LiveToast.put_toast(:error, "Nie masz dostępu do tej sekcji.")
       |> redirect(to: ~p"/")}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    {:halt,
     socket
     |> LiveToast.put_toast(:notice, "Musisz się zalogować.")
     |> redirect(to: ~p"/zaloguj")}
  end
end
