defmodule FirmowidWeb.Invoicing.CostInvoices.Views.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.InvoiceMatching

  @detail_loads [
    :is_deletable,
    :transactions,
    :original_invoice,
    :correction_invoices,
    :latest_correction_invoice,
    :effective_total_amount,
    :effective_currency,
    :effective_seller_display_name,
    :effective_seller_address,
    :effective_account_number,
    blob: [:url],
    correction_invoices: [blob: [:url]]
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    cost_invoice = CostInvoice.by_id!(id, load: @detail_loads, scope: scope)

    if is_nil(cost_invoice.original_invoice) do
      cost_invoice = Invoicing.hydrate_invoice_with_fa3_blob(cost_invoice)
      potential_transactions = InvoiceMatching.get_potential_transactions_for_invoice(cost_invoice, scope)

      socket =
        socket
        |> assign(:invoice, cost_invoice)
        |> assign(:potential_transactions, potential_transactions)
        |> assign(:current_user, current_user)
        |> assign(:no_padding, true)

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/kosztowe/#{cost_invoice.original_invoice.id}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      id="invoice-show"
      module={FirmowidWeb.Invoicing.Components.CostInvoiceDetails}
      invoice={@invoice}
      potential_transactions={@potential_transactions}
      current_user={@current_user}
      scope={@ash_scope}
    />
    """
  end

  # Event handlers -----------------------------------------------------------

  @impl true
  def handle_event("toggle-invoicing", _params, socket) do
    scope = socket.assigns.ash_scope
    invoice = Invoicing.toggle_cost_invoice_skip!(socket.assigns.invoice, scope: scope)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    Invoicing.delete_cost_invoice(socket.assigns.invoice.id, socket.assigns.ash_scope)

    {:noreply,
     socket
     |> put_flash(:info, "Faktura została usunięta")
     |> push_navigate(to: ~p"/fakturowanie?month=#{Date.to_iso8601(socket.assigns.invoice.issue_date)}")}
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => tx_id}, socket) do
    Invoicing.connect_cost_invoice_transactions(socket.assigns.invoice, [tx_id], scope: socket.assigns.ash_scope)

    invoice = CostInvoice.by_id!(socket.assigns.invoice.id, load: @detail_loads, scope: socket.assigns.ash_scope)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    Invoicing.disconnect_cost_invoice_transactions(socket.assigns.invoice,
      scope: socket.assigns.ash_scope
    )

    invoice = CostInvoice.by_id!(socket.assigns.invoice.id, load: @detail_loads, scope: socket.assigns.ash_scope)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_info(event, socket) do
    # Forward events to the assistant component
    send_update(FirmowidWeb.Invoicing.CostInvoices.Components.Assistant,
      id: "invoice-assistant",
      event: event
    )

    {:noreply, socket}
  end
end
