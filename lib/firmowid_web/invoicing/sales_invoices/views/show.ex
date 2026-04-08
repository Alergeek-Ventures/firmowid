defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analytics
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef
  alias FirmowidWeb.Core.Endpoint

  @item_calcs [:net_value, :vat_value, :gross_value]
  @detail_loads [
    :net_value,
    :vat_value,
    :gross_value,
    :is_deletable,
    :buyer_display_name_label,
    :transactions,
    sales_invoice_items: @item_calcs,
    corrections: [sales_invoice_items: @item_calcs],
    corrected_invoice: :corrections,
    latest_correction: [sales_invoice_items: @item_calcs]
  ]

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    current_user = socket.assigns.current_user

    scope = socket.assigns.ash_scope

    sales_invoice =
      case SalesInvoice.by_id(id, load: @detail_loads, scope: scope) do
        {:ok, invoice} ->
          invoice

        {:error, _} ->
          raise Ecto.NoResultsError,
            queryable: SalesInvoice
      end

    if sales_invoice.ksef_invoice_kind == :kor do
      # ensure `return_to` is preserved when redirecting to the corrected invoice
      params = Map.delete(params, "id")
      redirect_path = ~p"/sprzedazowe/#{sales_invoice.corrected_invoice_id}?#{params}"

      {:ok, redirect(socket, to: redirect_path)}
    else
      alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections

      potential_transactions = InvoiceMatching.get_potential_transactions_for_invoice(sales_invoice, scope)

      sales_invoice =
        then(sales_invoice, fn inv -> %{inv | corrections: AnnotatedCorrections.annotate(inv)} end)

      logo_url = Invoicing.get_logo_url(sales_invoice.organization_id, scope: scope)

      # Subscribe to KSeF status updates for live feedback
      Ksef.subscribe_ksef_status(current_user.organization_id)

      socket =
        socket
        |> assign(:invoice, sales_invoice)
        |> assign(:logo_url, logo_url)
        |> assign(:potential_transactions, potential_transactions)
        |> assign(:preview_url, "")
        |> assign(:preview_type, :html)
        |> assign(:no_padding, true)
        |> assign(:return_to, params["return_to"])
        |> assign(:ksef_connected?, Ksef.get_credential(socket.assigns.ash_scope) != nil)

      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      id="invoice-show"
      module={FirmowidWeb.Invoicing.Components.SalesInvoiceDetails}
      invoice={@invoice}
      logo_url={@logo_url}
      preview_url={@preview_url}
      preview_type={@preview_type}
      show_vat_for_sales_invoice={@current_org.is_vat_payer}
      potential_transactions={@potential_transactions}
      current_user={@current_user}
      return_to={@return_to}
      ksef_connected?={@ksef_connected?}
      scope={@ash_scope}
    />
    """
  end

  @impl true
  def handle_event("toggle-invoicing", _params, socket) do
    SalesInvoice.toggle_skip!(socket.assigns.invoice, scope: socket.assigns.ash_scope)
    invoice = refresh_invoice(socket.assigns.invoice.id, socket.assigns.ash_scope)

    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case SalesInvoice.destroy(socket.assigns.invoice, scope: socket.assigns.ash_scope) do
      :ok ->
        Analytics.track_event("sales_invoice_delete", socket.assigns.current_user, %{})

        {:noreply,
         socket
         |> put_flash(:info, "Faktura została usunięta")
         |> push_navigate(to: ~p"/fakturowanie?month=#{Date.to_iso8601(socket.assigns.invoice.issue_date)}")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie można usunąć faktury wysłanej do KSeF. Wystaw fakturę korygującą.")}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    case SalesInvoice.cancel(socket.assigns.invoice.id, scope: socket.assigns.ash_scope) do
      {:ok, correction} ->
        {:noreply,
         socket
         |> put_flash(:info, "Wystawiono korektę anulującą")
         |> push_navigate(to: ~p"/sprzedazowe/#{correction.id}/podsumowanie")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się anulować faktury")}
    end
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => tx_id}, socket) do
    user = socket.assigns.current_user

    Invoicing.connect_sales_invoice_transactions(socket.assigns.invoice, [tx_id], scope: socket.assigns.ash_scope)

    Analytics.track_event("sales_invoice_match", user, %{transaction_count: 1})

    invoice = refresh_invoice(socket.assigns.invoice.id, socket.assigns.ash_scope)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    Invoicing.disconnect_sales_invoice_transactions(socket.assigns.invoice,
      scope: socket.assigns.ash_scope
    )

    Analytics.track_event("sales_invoice_unmatch", socket.assigns.current_user, %{})

    invoice = refresh_invoice(socket.assigns.invoice.id, socket.assigns.ash_scope)
    {:noreply, assign(socket, :invoice, invoice)}
  end

  @impl true
  def handle_event("create_share_link", _params, socket) do
    invoice = socket.assigns.invoice

    case SalesInvoice.generate_share_token(invoice, scope: socket.assigns.ash_scope) do
      {:ok, updated_invoice} ->
        url = share_url(updated_invoice.share_token)

        {:noreply,
         socket
         |> assign(:invoice, updated_invoice)
         |> push_event("copy-to-clipboard", %{text: url})
         |> put_flash(:info, "Link skopiowany do schowka")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się utworzyć linku")}
    end
  end

  defp share_url(token) when is_binary(token) do
    Endpoint.url() <> "/faktura/" <> token
  end

  defp refresh_invoice(id, scope) do
    alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections

    invoice = Invoicing.get_sales_invoice!(id, load: @detail_loads, scope: scope)
    %{invoice | corrections: AnnotatedCorrections.annotate(invoice)}
  end

  @impl true
  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: status}}, socket) do
    # Handle KSeF submission status updates
    if socket.assigns.invoice.id == invoice_id do
      invoice = refresh_invoice(invoice_id, socket.assigns.ash_scope)

      # Update component with new invoice data
      send_update(FirmowidWeb.Invoicing.Components.SalesInvoiceDetails,
        id: "invoice-show",
        invoice: invoice
      )

      socket =
        socket
        |> assign(:invoice, invoice)
        |> ksef_status_flash(status)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(event, socket) do
    # Forward events to the assistant component
    send_update(FirmowidWeb.Invoicing.SalesInvoices.Components.Assistant,
      id: "invoice-assistant",
      event: event
    )

    {:noreply, socket}
  end

  defp ksef_status_flash(socket, :submitted), do: put_flash(socket, :info, "Faktura została wysłana do KSeF")

  defp ksef_status_flash(socket, :failed), do: put_flash(socket, :error, "Wysyłka do KSeF nie powiodła się")

  defp ksef_status_flash(socket, _status), do: socket
end
