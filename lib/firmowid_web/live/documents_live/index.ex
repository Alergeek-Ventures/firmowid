defmodule FirmowidWeb.DocumentsLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Documents.Document

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:form, to_form(Document.changeset(%Document{})))
      |> allow_upload(:file, accept: ~w(.pdf))
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())
      |> assign(:documents, Documents.list_documents_with_metadata())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"document" => document_params}, socket) do
    changeset =
      %Document{}
      |> Document.changeset(document_params)

    socket =
      socket
      |> assign(:form, to_form(changeset))

    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _, socket) do
    consume_uploaded_entries(socket, :file, fn %{path: path}, _entry ->
      {:ok, _document} =
        Documents.create_document({path, ".pdf"})

      {:ok, nil}
    end)

    socket =
      socket
      |> put_flash(:info, "Dokument został dodany")
      |> assign(:documents, Documents.list_documents_with_metadata())
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

    {:noreply, socket}
  end

  @impl true
  def handle_event("extract-metadata", %{"document-id" => document_id}, socket) do
    Documents.extract_invoice_info(document_id)

    socket =
      socket
      |> put_flash(:info, "Dokument został zaktualizowany")
      |> assign(:documents, Documents.list_documents_with_metadata())
      |> assign(:documents_pending_extraction, Documents.list_documents_without_metadata())

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

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Dokumenty")
  end
end
