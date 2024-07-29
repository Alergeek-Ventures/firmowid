defmodule FirmowidWeb.DocumentsLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Documents.Document

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:form, to_form(Document.changeset(%Document{})))
      |> assign(:documents, Documents.list_documents())
      |> allow_upload(:file, accept: ~w(.pdf), max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("validate", %{"document" => document_params}, socket) do
    changeset =
      Document.changeset(%Document{}, document_params)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form, to_form(changeset))

    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"document" => document_params}, socket) do
    with {:ok, document} <- Documents.create_document(document_params) do
      socket =
        socket
        |> put_flash(:info, "Dokument został dodany.")
        |> assign(:documents, [document | socket.assigns.documents])

      {:noreply, socket}
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dokumenty")
  end
end
