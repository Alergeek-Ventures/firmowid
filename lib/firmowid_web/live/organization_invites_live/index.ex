defmodule FirmowidWeb.OrganizationInvitesLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    socket =
      socket
      |> assign(:page_title, "Zaproszenia do twojej organizacji")
      |> assign(:organization_invites, Accounts.list_organization_invites(organization_id))

    {:ok, socket}
  end

  @impl true
  def handle_event("create", _, socket) do
    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    with {:ok, _} <-
           Accounts.create_organization_invites(
             organization_id,
             current_user.id
           ) do
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    organization_invites = Accounts.get_organization_invites!(id, organization_id)
    {:ok, _} = Accounts.delete_organization_invites(organization_id, organization_invites)

    socket =
      socket
      |> assign(:organization_invites, Accounts.list_organization_invites(organization_id))

    {:noreply, socket}
  end
end
