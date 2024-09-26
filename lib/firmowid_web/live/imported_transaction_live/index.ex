defmodule FirmowidWeb.ImportedTransactionLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Finances

  @impl true
  def mount(_params, _session, socket) do
    transactions =
      Finances.list_imported_transactions()
      |> Enum.map(fn t ->
        Map.merge(t, %{
          amount:
            Money.new(
              t.transaction_currency,
              t.transaction_amount
            )
        })
      end)

    stream =
      socket
      |> stream_configure(:imported_transactions,
        dom_id: &"imported_transactions-#{&1.transaction_id}"
      )
      |> stream(:imported_transactions, transactions)

    {:ok, stream}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       params
     )}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Imported transactions")
    |> assign(:imported_transaction, nil)
  end

  @impl true
  def handle_info(
        {FirmowidWeb.ImportedTransactionLive.FormComponent, {:saved, imported_transaction}},
        socket
      ) do
    {:noreply, stream_insert(socket, :imported_transactions, imported_transaction)}
  end

  @impl true
  def handle_event("delete", %{"transaction_id" => transaction_id}, socket) do
    imported_transaction = Finances.get_imported_transaction!(transaction_id)
    {:ok, _} = Finances.delete_imported_transaction(imported_transaction)

    {:noreply, stream_delete(socket, :imported_transactions, imported_transaction)}
  end
end
