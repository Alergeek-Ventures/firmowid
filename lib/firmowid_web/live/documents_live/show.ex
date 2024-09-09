defmodule FirmowidWeb.DocumentsLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.InvoiceMatcher

  @impl true
  def mount(params, _session, socket) do
    document = Documents.get_document(params["id"])

    potential_transactions =
      InvoiceMatcher.get_potential_transactions_for_document(document)
      |> Enum.map(fn t ->
        Map.merge(t, %{
          amount:
            Money.from_float!(
              t.transaction_currency,
              t.transaction_amount
            )
        })
      end)

    socket =
      socket
      |> assign(:document, document)
      |> assign(:potential_transactions, potential_transactions)

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
  def handle_event(
        "connect",
        %{
          "document-id" => document_id,
          "imported-transaction-id" => imported_transaction_id
        },
        socket
      ) do
    Documents.create_documents_imported_transactions_connection(
      document_id,
      imported_transaction_id
    )

    document = Documents.get_document(document_id)

    socket =
      socket
      |> assign(:document, document)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "disconnect",
        %{"document-id" => document_id, "imported-transaction-id" => imported_transaction_id},
        socket
      ) do
    Documents.delete_documents_imported_transactions_connection(
      document_id,
      imported_transaction_id
    )

    document = Documents.get_document(document_id)

    socket =
      socket
      |> assign(:document, document)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-skip-invoicing", _, socket) do
    skip_invoicing = socket.assigns.document.skip_invoicing

    Documents.update_document(socket.assigns.document.id, %{
      skip_invoicing: !skip_invoicing
    })

    document = Documents.get_document(socket.assigns.document.id)

    socket =
      socket
      |> assign(:document, document)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "delete",
        %{"document-id" => document_id},
        socket
      ) do
    Documents.delete_document(document_id)

    socket =
      socket
      |> put_flash(:info, "Dokument został usunięty.")
      |> push_navigate(to: ~p"/documents")

    {:noreply, socket}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, "Podgląd dokumentu #{params["id"]}")
  end
end
