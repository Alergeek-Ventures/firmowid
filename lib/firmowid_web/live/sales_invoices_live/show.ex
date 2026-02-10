defmodule FirmowidWeb.SalesInvoicesLive.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analytics
  alias Firmowid.Invoicing
  alias Firmowid.Ksef
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    current_user = socket.assigns.current_user

    sales_invoice = SalesInvoices.get_sales_invoice(id)
    Bodyguard.permit!(SalesInvoices, :show, current_user, sales_invoice)

    potential_transactions = Invoicing.get_potential_transactions_for_invoice(sales_invoice)

    sales_invoice =
      id
      |> SalesInvoices.get_sales_invoice_with_logo_url()
      |> Repo.preload([:corrected_invoice])

    # Subscribe to KSeF status updates for live feedback
    Ksef.subscribe_ksef_status(current_user.organization_id)

    socket =
      socket
      |> assign(:invoice, sales_invoice)
      |> assign(:reference_invoice, get_reference_invoice(sales_invoice))
      |> assign(:potential_transactions, potential_transactions)
      |> assign(:preview_url, "")
      |> assign(:preview_type, :html)
      |> assign(:no_padding, true)
      |> assign(:return_to, params["return_to"])
      |> assign(:ksef_connected?, Ksef.get_credential() != nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      id="invoice-show"
      module={FirmowidWeb.Components.Invoicing.SalesInvoiceDetails}
      invoice={@invoice}
      reference_invoice={@reference_invoice}
      preview_url={@preview_url}
      preview_type={@preview_type}
      show_vat_for_sales_invoice={@current_org.is_vat_payer}
      potential_transactions={@potential_transactions}
      current_user={@current_user}
      return_to={@return_to}
      ksef_connected?={@ksef_connected?}
    />
    """
  end

  @impl true
  def handle_event("toggle-invoicing", _params, socket) do
    Bodyguard.permit!(SalesInvoices, :update, socket.assigns.current_user, socket.assigns.invoice)

    SalesInvoices.toggle_skip_invoicing(socket.assigns.invoice.id)
    invoice = refresh_invoice(socket.assigns.invoice.id)

    {:noreply,
     socket
     |> assign(:invoice, invoice)
     |> assign(:reference_invoice, get_reference_invoice(invoice))}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    Bodyguard.permit!(SalesInvoices, :delete, socket.assigns.current_user, socket.assigns.invoice)

    case SalesInvoices.delete_sales_invoice(socket.assigns.invoice) do
      {:ok, _deleted} ->
        Analytics.track_event("sales_invoice_delete", socket.assigns.current_user, %{})

        {:noreply,
         socket
         |> put_flash(:info, "Faktura została usunięta")
         |> push_navigate(to: ~p"/fakturowanie?month=#{Date.to_iso8601(socket.assigns.invoice.issue_date)}")}

      {:error, :ksef_submitted} ->
        {:noreply, put_flash(socket, :error, "Nie można usunąć faktury wysłanej do KSeF. Wystaw fakturę korygującą.")}
    end
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
    id
    |> SalesInvoices.get_sales_invoice_with_logo_url()
    |> Repo.preload([:corrected_invoice])
  end

  @impl true
  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: status}}, socket) do
    # Handle KSeF submission status updates
    if socket.assigns.invoice.id == invoice_id do
      invoice = refresh_invoice(invoice_id)

      # Update component with new invoice data
      send_update(FirmowidWeb.Components.Invoicing.SalesInvoiceDetails,
        id: "invoice-show",
        invoice: invoice,
        reference_invoice: get_reference_invoice(invoice)
      )

      socket =
        socket
        |> assign(:invoice, invoice)
        |> assign(:reference_invoice, get_reference_invoice(invoice))
        |> ksef_status_flash(status)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(event, socket) do
    # Forward events to the assistant component
    send_update(FirmowidWeb.SalesInvoicesLive.Assistant,
      id: "invoice-assistant",
      event: event
    )

    {:noreply, socket}
  end

  defp ksef_status_flash(socket, :submitted), do: put_flash(socket, :info, "Faktura została wysłana do KSeF")

  defp ksef_status_flash(socket, :failed), do: put_flash(socket, :error, "Wysyłka do KSeF nie powiodła się")

  defp ksef_status_flash(socket, _status), do: socket

  defp get_reference_invoice(%SalesInvoices.SalesInvoice{ksef_invoice_kind: :kor} = invoice) do
    SalesInvoices.get_reference_invoice_for_correction(invoice)
  end

  defp get_reference_invoice(_invoice), do: nil
end
