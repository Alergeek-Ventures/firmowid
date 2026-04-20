defmodule FirmowidWeb.Organization.Invites.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Forbidden
  alias Firmowid.Ash.Core

  @invite_load [issued_by: [:email], consumed_by: [:email]]

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może przeglądać zaproszenia."
    end

    invites =
      Core.list_invites!(load: @invite_load, scope: scope)

    socket =
      socket
      |> assign(:page_title, "Zaproszenia do twojej organizacji")
      |> assign(:organization_invites, invites)

    {:ok, socket}
  end

  @impl true
  def handle_event("create", _, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może tworzyć zaproszenia."
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

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może usuwać zaproszenia."
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
