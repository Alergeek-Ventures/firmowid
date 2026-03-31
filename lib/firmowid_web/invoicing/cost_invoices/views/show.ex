defmodule FirmowidWeb.Invoicing.CostInvoices.Views.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analytics
  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Invoicing

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    cost_invoice = AshCostInvoice.get_with_blob_url!(id, scope: scope)
    Bodyguard.permit!(Invoicing, :show, current_user)

    if is_nil(cost_invoice.original_invoice) do
      cost_invoice = AshCostInvoice.hydrate_invoice_with_fa3_blob(cost_invoice)
      potential_transactions = Invoicing.get_potential_transactions_for_invoice(cost_invoice)

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
    />
    """
  end

  # Event handlers -----------------------------------------------------------

  @impl true
  def handle_event("toggle-invoicing", _params, socket) do
    Bodyguard.permit!(Invoicing, :update, socket.assigns.current_user)
    invoice = AshCostInvoice.toggle_skip_invoicing(socket.assigns.invoice.id)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    Bodyguard.permit!(Invoicing, :update, socket.assigns.current_user)
    AshCostInvoice.delete_cost_invoice(socket.assigns.invoice.id)

    Analytics.track_event("cost_invoice_delete", socket.assigns.current_user, %{})

    {:noreply,
     socket
     |> put_flash(:info, "Faktura została usunięta")
     |> push_navigate(to: ~p"/fakturowanie?month=#{Date.to_iso8601(socket.assigns.invoice.issue_date)}")}
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => tx_id}, socket) do
    user = socket.assigns.current_user

    Bodyguard.permit!(Invoicing, :update, user)

    # TODO: replace authorize?: false + actor: %{} with system actor once available
    CostInvoiceTransaction.create_connections(
      [socket.assigns.invoice.id],
      [tx_id],
      user.organization_id,
      authorize?: false,
      actor: %{}
    )

    Analytics.track_event("cost_invoice_match", user, %{transaction_count: 1})

    invoice = AshCostInvoice.get_with_blob_url!(socket.assigns.invoice.id, scope: socket.assigns.ash_scope)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    Bodyguard.permit!(Invoicing, :update, socket.assigns.current_user)
    # TODO: replace authorize?: false + actor: %{} with system actor once available
    CostInvoiceTransaction.delete_for_invoice(socket.assigns.invoice.id, authorize?: false, actor: %{})
    AshCostInvoice.broadcast_cost_invoice_list_updated(socket.assigns.current_user.organization_id)

    Analytics.track_event("cost_invoice_unmatch", socket.assigns.current_user, %{})

    invoice = AshCostInvoice.get_with_blob_url!(socket.assigns.invoice.id, scope: socket.assigns.ash_scope)
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
