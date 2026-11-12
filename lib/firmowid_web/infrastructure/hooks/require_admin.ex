defmodule FirmowidWeb.Infrastructure.Hooks.RequireAdmin do
  @moduledoc """
  LiveView on_mount hook. Requires the organization admin role.

  An admin-only LiveView declares `on_mount {RequireAdmin, :default}`; a view
  shared with members uses `:managing_employee`, which requires the admin only on
  the route under an employee. Both must run after `RequireOrganization`, which
  assigns the user and organization.
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

  # The business trip form also serves a member's own trip; only the route under
  # an employee, which carries the employee's id, is the admin's.
  def on_mount(:managing_employee, %{"id" => _employee_id} = params, session, socket),
    do: on_mount(:default, params, session, socket)

  def on_mount(:managing_employee, _params, _session, socket), do: {:cont, socket}
end
