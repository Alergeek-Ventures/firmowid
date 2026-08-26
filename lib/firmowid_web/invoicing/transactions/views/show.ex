defmodule FirmowidWeb.Invoicing.Transactions.Views.Show do
  @moduledoc """
  Transaction details page with source account information and assistant access.
  """

  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias FirmowidWeb.Invoicing.Assistant.Utilities.SessionCloser
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Transactions.Components.ShowComponents
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @transaction_loads [
    :bank_account,
    :direction,
    :signed_amount,
    :counterparty_display_name,
    cost_invoices: [
      :invoice_source,
      :effective_total_amount,
      :effective_currency,
      :effective_seller_display_name,
      :issue_date,
      :invoice_identifier
    ],
    sales_invoices: [
      :gross_value,
      :currency,
      :buyer_display_name_label,
      :issue_date,
      :invoice_number,
      sales_invoice_items: [:name]
    ]
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:chat, false)
     |> assign(:no_padding, true)
     |> assign(:return_to, nil)}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    scope = socket.assigns.ash_scope
    transaction = Finances.get_transaction!(id, load: @transaction_loads, scope: scope)
    return_to = Navigation.return_to_path(params["powrot_do"])

    {:noreply,
     socket
     |> maybe_reset_chat(id)
     |> assign(:return_to, return_to)
     |> assign_transaction(transaction)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="transaction-show" class="flex flex-col">
      <ShowComponents.header transaction={@transaction} return_to={@return_to} />

      <div class="flex min-w-0 flex-col bg-white lg:flex-row">
        <ShowComponents.details_sidebar transaction={@transaction} />

        <InvoiceDetails.main>
          <%= cond do %>
            <% @chat -> %>
              <ShowComponents.assistant_state
                transaction={@transaction}
                current_user={@current_user}
                scope={@ash_scope}
                return_to={@return_to}
              />
            <% @transaction.skip_invoicing -> %>
              <ShowComponents.transaction_skipped_view />
            <% linked_invoices?(@transaction) -> %>
              <ShowComponents.linked_state transaction={@transaction} return_to={@return_to} />
            <% true -> %>
              <ShowComponents.empty_state transaction={@transaction} />
          <% end %>
        </InvoiceDetails.main>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("show_chat", _params, socket) do
    {:noreply, assign(socket, :chat, true)}
  end

  def handle_event("close_chat", params, socket) do
    SessionCloser.close(params, socket.assigns.ash_scope)
    {:noreply, assign(socket, :chat, false)}
  end

  def handle_event("toggle-invoicing", _params, socket) do
    scope = socket.assigns.ash_scope
    transaction = socket.assigns.transaction

    Finances.set_transaction_skip_invoicing!(
      transaction,
      %{skip_invoicing: !transaction.skip_invoicing},
      scope: scope
    )

    {:noreply, assign_transaction(socket, reload_transaction(transaction.id, scope))}
  end

  def handle_event("unlink_all", _params, socket) do
    transaction = socket.assigns.transaction
    scope = socket.assigns.ash_scope

    result = Invoicing.disconnect_transaction_from_all_invoices_manual(transaction, scope)

    case result do
      {:ok, _transaction} ->
        {:noreply, assign_transaction(socket, reload_transaction(transaction.id, scope))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się odłączyć faktur")}
    end
  end

  defp linked_invoices?(transaction) do
    transaction.cost_invoices != [] or transaction.sales_invoices != []
  end

  defp reload_transaction(id, scope) do
    Finances.get_transaction!(id, load: @transaction_loads, scope: scope)
  end

  defp assign_transaction(socket, transaction) do
    assign(socket, :transaction, transaction)
  end

  defp maybe_reset_chat(socket, id) do
    case socket.assigns[:transaction] do
      %Transaction{id: ^id} -> socket
      _ -> assign(socket, :chat, false)
    end
  end
end
