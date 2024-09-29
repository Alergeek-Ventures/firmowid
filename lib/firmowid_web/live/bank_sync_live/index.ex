defmodule FirmowidWeb.BankSyncLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.GoLimitless
  alias Firmowid.GoLimitless.Requisition
  alias Firmowid.InvoiceMatcher

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    {:ok,
     stream(
       socket,
       :requisitions,
       GoLimitless.list_requisitions(organization_id)
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:requisition, %Requisition{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Synchronizacja konta bankowego z Firmowidem")
    |> assign(:requisition, nil)
  end

  @impl true
  def handle_info({FirmowidWeb.RequisitionLive.FormComponent, {:saved, requisition}}, socket) do
    {:noreply, stream_insert(socket, :requisitions, requisition)}
  end

  @impl true
  def handle_event("sync", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    requisition = GoLimitless.get_requisition!(id)

    GoLimitless.ApiClient.sync_transaction_for_account(
      "PL33105014451000009081121700",
      requisition.requisition_id,
      organization_id
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("auto-match-documents", _, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id
    InvoiceMatcher.match_all_good_candidates_for_unconnected_documents(organization_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    requisition = GoLimitless.get_requisition!(id)
    {:ok, _} = GoLimitless.delete_requisition(requisition)

    {:noreply, stream_delete(socket, :requisitions, requisition)}
  end
end
