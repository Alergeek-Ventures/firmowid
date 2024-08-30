defmodule FirmowidWeb.DocumentsLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Documents.Document

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Documents.subscribe()

    socket =
      socket
      |> assign(:form, to_form(Document.changeset(%Document{})))
      |> allow_upload(:file, accept: ~w(.pdf), progress: &handle_progress/3, auto_upload: true)
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())
      |> assign(:documents, Documents.list_documents_with_metadata())

    {:ok, socket}
  end

  defp handle_progress(:file, entry, socket) do
    if entry.done? do
      consume_uploaded_entries(socket, :file, fn %{path: path}, _entry ->
        {:ok, document} =
          Documents.create_document({path, ".pdf"})

        Documents.start_extraction_job(document.id)

        {:ok, nil}
      end)

      socket =
        socket
        |> put_flash(:info, "Dokument został dodany")
        |> assign(:documents, Documents.list_documents_with_metadata())
        |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  @impl true
  def handle_event("upload", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"document-id" => document_id}, socket) do
    Documents.delete_document(document_id)

    socket =
      socket
      |> put_flash(:info, "Dokument został usunięty.")
      |> assign(:documents, Documents.list_documents_with_metadata())
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

    {:noreply, socket}
  end

  @impl true
  def handle_info({:document_updated, _}, socket) do
    socket =
      socket
      |> assign(:documents, Documents.list_documents_with_metadata())
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dokumenty")
  end
end
