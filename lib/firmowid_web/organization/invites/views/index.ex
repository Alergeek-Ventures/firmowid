defmodule FirmowidWeb.Organization.Invites.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.EmptyState
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Core
  alias FirmowidUI.Utilities.ForbiddenError

  @invite_load [issued_by: [:email], consumed_by: [:email]]

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    if current_user.member.role != :admin do
      raise ForbiddenError, gettext("Only an administrator can view invitations.")
    end

    invites =
      Core.list_invites!(load: @invite_load, scope: scope)

    socket =
      socket
      |> assign(:page_title, pgettext("page title", "Invitations to your organization"))
      |> assign(:organization_invites, invites)

    {:ok, socket}
  end

  @impl true
  def handle_event("create", _, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    if current_user.member.role != :admin do
      raise ForbiddenError, gettext("Only an administrator can create invitations.")
    end

    Core.create_invite!(%{issued_by_id: current_user.id}, scope: scope)

    invites =
      Core.list_invites!(load: @invite_load, scope: scope)

    socket =
      assign(socket, :organization_invites, invites)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    if current_user.member.role != :admin do
      raise ForbiddenError, gettext("Only an administrator can delete invitations.")
    end

    invite =
      Core.get_invite!(id, scope: scope)

    Core.destroy_invite!(invite, scope: scope)

    invites =
      Core.list_invites!(load: @invite_load, scope: scope)

    socket =
      assign(socket, :organization_invites, invites)

    {:noreply, socket}
  end
end
