defmodule FirmowidWeb.ImportedTransactionLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents
  alias Firmowid.Finances
  # alias Firmowid.InvoiceMatcher

  @impl true
  def mount(params, _session, socket) do
    imported_transaction = Finances.get_imported_transaction!(params["id"])

    # potential_documents =
    #   InvoiceMatcher.get_potential_transactions_for_imported_transaction(imported_transaction)

    socket =
      socket
      |> assign(:imported_transaction, imported_transaction)

    # |> assign(:potential_documents, potential_documents)

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

    imported_transaction = Finances.get_imported_transaction!(imported_transaction_id)

    socket =
      socket
      |> assign(:imported_transaction, imported_transaction)

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

    imported_transaction = Finances.get_imported_transaction!(imported_transaction_id)

    socket =
      socket
      |> assign(:imported_transaction, imported_transaction)

    {:noreply, socket}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, "Podgląd transakcji #{params["id"]}")
  end
end
