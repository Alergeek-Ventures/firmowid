defmodule FirmowidWeb.RequisitionLive.Index do
  alias Swoosh.ApiClient
  use FirmowidWeb, :live_view

  alias Firmowid.GoLimitless
  alias Firmowid.GoLimitless.ApiClient
  alias Firmowid.GoLimitless.Requisition

  @impl true
  def mount(_params, _session, socket) do
    institutions =
      ApiClient.get_available_institutions()
      |> Enum.map(&{&1["id"], &1})
      |> Enum.slice(10..20)

    socket =
      socket
      |> assign(institutions: institutions)

    {:ok,
     stream(
       socket,
       :requisitions,
       GoLimitless.list_requisitions()
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Requisition")
    |> assign(:requisition, GoLimitless.get_requisition!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Requisition")
    |> assign(:requisition, %Requisition{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Requisitions")
    |> assign(:requisition, nil)
  end

  @impl true
  def handle_info({FirmowidWeb.RequisitionLive.FormComponent, {:saved, requisition}}, socket) do
    {:noreply, stream_insert(socket, :requisitions, requisition)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    requisition = GoLimitless.get_requisition!(id)
    {:ok, _} = GoLimitless.delete_requisition(requisition)

    {:noreply, stream_delete(socket, :requisitions, requisition)}
  end
end
