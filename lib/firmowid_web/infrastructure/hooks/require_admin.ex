defmodule FirmowidWeb.Infrastructure.Hooks.RequireAdmin do
  @moduledoc """
  LiveView on_mount hook. Requires admin role.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, %{assigns: %{current_user: %{member: %{role: :admin}}}} = socket) do
    {:cont, socket}
  end

  def on_mount(:default, _params, _session, socket) do
    {:halt,
     socket
     |> LiveToast.put_toast(:error, gettext("You do not have access to the management section."))
     |> redirect(to: ~p"/czasosledz")}
  end
end
