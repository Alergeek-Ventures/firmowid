defmodule FirmowidWeb.Infrastructure.Hooks.RequireAdmin do
  @moduledoc """
  LiveView on_mount hook. Requires admin role.
  """

  use FirmowidWeb, :verified_routes

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, %{assigns: %{current_user: %{role: :admin}}} = socket) do
    {:cont, socket}
  end

  def on_mount(:default, _params, _session, socket) do
    {:halt,
     socket
     |> LiveToast.put_toast(:error, "Nie masz dostępu do sekcji zarządzania.")
     |> redirect(to: ~p"/czasosledz")}
  end
end
