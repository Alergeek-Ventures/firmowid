defmodule FirmowidWeb.BankSyncLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.BankData

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    socket =
      socket
      |> assign(
        :requisitions,
        BankData.list_requisitions(organization_id)
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket =
      socket
      |> assign(:page_title, "Synchronizacja konta bankowego z Firmowidem")

    {:noreply, socket}
  end

  @impl true
  def handle_event("sync", %{"requisition-id" => requisition_id}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    BankData.sync_requisition(requisition_id, organization_id)
    LiveToast.send_toast(:info, "Zsynchronizowano konto bankowe.")

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"requisition-id" => requisition_id}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    BankData.delete_requisition(requisition_id, organization_id)

    socket =
      socket
      |> assign(
        :requisitions,
        BankData.list_requisitions(organization_id)
      )

    {:noreply, socket}
  end
end
