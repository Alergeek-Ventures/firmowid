defmodule FirmowidWeb.OrganizationInvitesLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts
  alias Posthog

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    Bodyguard.permit!(Accounts, :read_organization_invites, current_user)

    socket =
      socket
      |> assign(:page_title, "Zaproszenia do twojej organizacji")
      |> assign(:organization_invites, Accounts.list_organization_invites(organization_id))

    {:ok, socket}
  end

  @impl true
  def handle_event("create", _, socket) do
    current_user = socket.assigns.current_user
    Bodyguard.permit!(Accounts, :create_organization_invite, current_user)

    organization_id = current_user.organization_id

    with {:ok, invite} <-
           Accounts.create_organization_invites(
             organization_id,
             current_user.id
           ) do
      Posthog.capture("organization_invite_created", current_user.id, %{
        organization_id: organization_id,
        invite_id: invite.id,
        expires_at: invite.expires_at
      })

      socket =
        socket
        |> assign(:organization_invites, Accounts.list_organization_invites(organization_id))

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    Bodyguard.permit!(Accounts, :delete_organization_invite, current_user)

    organization_id = current_user.organization_id

    organization_invites = Accounts.get_organization_invites!(id, organization_id)
    {:ok, _} = Accounts.delete_organization_invites(organization_id, organization_invites)

    socket =
      assign(socket, :organization_invites, Accounts.list_organization_invites(organization_id))

    {:noreply, socket}
  end
end
