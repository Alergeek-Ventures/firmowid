defmodule FirmowidWeb.Infrastructure.Hooks.RequireAdmin do
  @moduledoc """
  LiveView on_mount hook. Requires admin role.
  """

  use FirmowidWeb, :verified_routes
  use Gettext, backend: Firmowid.Gettext

  import Phoenix.LiveView

  alias FirmowidWeb.Infrastructure.UserAuth

  def on_mount(:default, _params, _session, %{assigns: %{current_user: %{member: %{role: :admin}}}} = socket) do
    {:cont, socket}
  end

  def on_mount(:default, _params, _session, %{assigns: %{current_user: user, current_org: org}} = socket) do
    {:halt,
     socket
     |> LiveToast.put_toast(:error, gettext("You do not have access to the management section."))
     |> redirect(to: UserAuth.signed_in_path_for_user(user, org.id))}
  end
end
