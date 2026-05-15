defmodule FirmowidWeb.Invoicing.CostInvoices.Views.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @detail_loads [
    :invoice_source,
    :is_deletable,
    :internal_note,
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
    correction_invoices: [:internal_note, blob: [:url]]
  ]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope
    return_to = Navigation.return_to_path(params["powrot_do"])

    cost_invoice = CostInvoice.by_id!(id, load: @detail_loads, scope: scope)

    if is_nil(cost_invoice.original_invoice) do
      cost_invoice = Invoicing.hydrate_invoice_with_fa3_blob(cost_invoice)

      potential_transactions =
        InvoiceMatching.get_potential_transactions_for_invoice(cost_invoice, scope)

      socket =
        socket
        |> assign(:invoice, cost_invoice)
        |> assign(:potential_transactions, potential_transactions)
        |> assign(:current_user, current_user)
        |> assign(:return_to, return_to)
        |> assign(:no_padding, true)

      {:ok, socket}
    else
      {:ok,
       redirect(socket,
         to: Navigation.cost_invoice_show_path(cost_invoice.original_invoice.id, return_to)
       )}
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
      return_to={@return_to}
      scope={@ash_scope}
    />
    """
  end

  # Event handlers -----------------------------------------------------------

  @impl true
  def handle_event("toggle-invoicing", _params, socket) do
    scope = socket.assigns.ash_scope
    Invoicing.toggle_cost_invoice_skip!(socket.assigns.invoice, scope: scope)
    invoice = CostInvoice.by_id!(socket.assigns.invoice.id, load: @detail_loads, scope: scope)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("pdf-download-error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Nie udało się wygenerować PDF")}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    Invoicing.delete_cost_invoice(socket.assigns.invoice.id, socket.assigns.ash_scope)

    {:noreply,
     socket
     |> put_flash(:info, "Faktura została usunięta")
     |> push_navigate(
       to:
         socket.assigns.return_to ||
           Navigation.default_invoicing_path(socket.assigns.invoice.issue_date)
     )}
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => tx_id}, socket) do
    Invoicing.connect_cost_invoice_transactions_manual(
      socket.assigns.invoice,
      [tx_id],
      socket.assigns.ash_scope
    )

    invoice =
      CostInvoice.by_id!(socket.assigns.invoice.id,
        load: @detail_loads,
        scope: socket.assigns.ash_scope
      )

    potential_transactions =
      InvoiceMatching.get_potential_transactions_for_invoice(invoice, socket.assigns.ash_scope)

    {:noreply,
     socket
     |> assign(:invoice, invoice)
     |> assign(:potential_transactions, potential_transactions)}
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    case Invoicing.disconnect_all_cost_invoice_transactions_manual(
           socket.assigns.invoice,
           socket.assigns.ash_scope
         ) do
      {:ok, _invoice} ->
        invoice =
          CostInvoice.by_id!(socket.assigns.invoice.id,
            load: @detail_loads,
            scope: socket.assigns.ash_scope
          )

        potential_transactions =
          InvoiceMatching.get_potential_transactions_for_invoice(
            invoice,
            socket.assigns.ash_scope
          )

        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> assign(:potential_transactions, potential_transactions)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się odłączyć transakcji")}
    end
  end

  @impl true
  def handle_info(event, socket) do
    _ = event
    {:noreply, socket}
  end
end
