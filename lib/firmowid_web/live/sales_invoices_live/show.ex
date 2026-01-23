defmodule FirmowidWeb.SalesInvoicesLive.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analytics
  alias Firmowid.Invoicing
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user

    sales_invoice = SalesInvoices.get_sales_invoice(id)
    Bodyguard.permit!(SalesInvoices, :show, current_user, sales_invoice)

    potential_transactions = Invoicing.get_potential_transactions_for_invoice(sales_invoice)

    sales_invoice = SalesInvoices.get_sales_invoice_with_logo_url(id)

    socket =
      socket
      |> assign(:invoice, sales_invoice)
      |> assign(:potential_transactions, potential_transactions)
      |> assign(:preview_url, "")
      |> assign(:preview_type, :html)
      |> assign(:no_padding, true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      id="invoice-show"
      module={FirmowidWeb.Components.Invoicing.SalesInvoiceDetails}
      invoice={@invoice}
      preview_url={@preview_url}
      preview_type={@preview_type}
      show_vat_for_sales_invoice={@current_org.is_vat_payer}
      potential_transactions={@potential_transactions}
      current_user={@current_user}
    />
    """
  end

  @impl true
  def handle_event("toggle-invoicing", _params, socket) do
    Bodyguard.permit!(SalesInvoices, :update, socket.assigns.current_user, socket.assigns.invoice)

    SalesInvoices.toggle_skip_invoicing(socket.assigns.invoice.id)
    invoice = refresh_invoice(socket.assigns.invoice.id)

    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    Bodyguard.permit!(SalesInvoices, :delete, socket.assigns.current_user, socket.assigns.invoice)
    SalesInvoices.delete_sales_invoice(%SalesInvoice{id: socket.assigns.invoice.id})

    Analytics.track_event("sales_invoice_delete", socket.assigns.current_user, %{})

    {:noreply,
     socket
     |> put_flash(:info, "Faktura została usunięta")
     |> push_navigate(to: ~p"/fakturowanie?month=#{Date.to_iso8601(socket.assigns.invoice.issue_date)}")}
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => tx_id}, socket) do
    Bodyguard.permit!(SalesInvoices, :update, socket.assigns.current_user, socket.assigns.invoice)
    user = socket.assigns.current_user

    SalesInvoices.create_sales_invoices_transactions_connection(
      socket.assigns.invoice.id,
      tx_id,
      user.organization_id
    )

    Analytics.track_event("sales_invoice_match", user, %{transaction_count: 1})

    invoice = refresh_invoice(socket.assigns.invoice.id)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    Bodyguard.permit!(SalesInvoices, :update, socket.assigns.current_user, socket.assigns.invoice)
    SalesInvoices.delete_sales_invoices_transactions_connections(socket.assigns.invoice.id)

    Analytics.track_event("sales_invoice_unmatch", socket.assigns.current_user, %{})

    invoice = refresh_invoice(socket.assigns.invoice.id)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  defp refresh_invoice(id) do
    SalesInvoices.get_sales_invoice_with_logo_url(id)
  end

  @impl true
  def handle_info(event, socket) do
    # Forward events to the assistant component
    send_update(FirmowidWeb.SalesInvoicesLive.Assistant,
      id: "invoice-assistant",
      event: event
    )

    {:noreply, socket}
  end
end
