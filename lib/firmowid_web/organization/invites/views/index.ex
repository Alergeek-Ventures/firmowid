defmodule FirmowidWeb.Organization.Invites.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Ash.Error.Forbidden
  alias Firmowid.Analytics
  alias Firmowid.Ash.Core

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może przeglądać zaproszenia."
    end

    invites =
      Core.list_invites!(tenant: organization_id, authorize?: false, actor: %{})

    socket =
      socket
      |> assign(:page_title, "Zaproszenia do twojej organizacji")
      |> assign(:organization_invites, invites)

    {:ok, socket}
  end

  @impl true
  def handle_event("create", _, socket) do
    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może tworzyć zaproszenia."
    end

    invite =
      Core.create_invite!(%{issued_by_id: current_user.id},
        tenant: organization_id,
        authorize?: false,
        actor: %{}
      )

    Analytics.track_event("organization_invite_created", current_user, %{
      organization_id: organization_id,
      invite_id: invite.id
    })

    invites =
      Core.list_invites!(tenant: organization_id, authorize?: false, actor: %{})

    socket =
      assign(socket, :organization_invites, invites)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może usuwać zaproszenia."
    end

    invite =
      Core.get_invite!(id, tenant: organization_id, authorize?: false, actor: %{})

    Core.destroy_invite!(invite, tenant: organization_id, authorize?: false, actor: %{})

    invites =
      Core.list_invites!(tenant: organization_id, authorize?: false, actor: %{})

    socket =
      assign(socket, :organization_invites, invites)

    {:noreply, socket}
  end
end
