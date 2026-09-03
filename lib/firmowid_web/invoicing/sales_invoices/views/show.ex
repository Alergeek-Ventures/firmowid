defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceSharing
  alias Firmowid.Ash.Ksef
  alias Firmowid.ErrorKind
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  require Logger

  @item_calcs [:net_value, :vat_value, :gross_value]
  @detail_loads [
    :invoice_source,
    :net_value,
    :vat_value,
    :gross_value,
    :amount,
    :effective_amount,
    :is_deletable,
    :buyer_display_name_label,
    transactions: [:amount],
    sales_invoice_items: @item_calcs,
    corrections: [:amount, :email_deliveries, sales_invoice_items: @item_calcs],
    corrected_invoice: :corrections,
    email_deliveries: [],
    latest_correction: [:amount, sales_invoice_items: @item_calcs]
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

    return_to = Navigation.return_to_path(params["powrot_do"])

    if sales_invoice.ksef_invoice_kind == :kor do
      redirect_path =
        Navigation.sales_invoice_show_path(sales_invoice.corrected_invoice_id, return_to)

      {:ok, redirect(socket, to: redirect_path)}
    else
      alias Firmowid.Ash.Invoicing.Calculations.AnnotatedCorrections

      potential_transactions =
        InvoiceMatching.get_potential_transactions_for_invoice(sales_invoice, scope)

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
        |> assign(:return_to, return_to)
        |> assign(:ksef_connected?, Ksef.connected?(socket.assigns.ash_scope))

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
  def handle_event("pdf-download-error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Nie udało się wygenerować PDF")}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case SalesInvoice.destroy(socket.assigns.invoice, scope: socket.assigns.ash_scope) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Faktura została usunięta")
         |> push_navigate(
           to:
             socket.assigns.return_to ||
               Navigation.default_invoicing_path(socket.assigns.invoice.issue_date)
         )}

      {:error, _error} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Nie można usunąć faktury wysłanej do KSeF. Wystaw fakturę korygującą."
         )}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    case SalesInvoice.cancel(socket.assigns.invoice.id, scope: socket.assigns.ash_scope) do
      {:ok, correction} ->
        submit_cancellation_correction(socket, correction)

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się anulować faktury")}
    end
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => tx_id}, socket) do
    case Invoicing.connect_sales_invoice_transactions_manual(
           socket.assigns.invoice,
           [tx_id],
           socket.assigns.ash_scope
         ) do
      {:ok, _connected_invoice} ->
        invoice = refresh_invoice(socket.assigns.invoice.id, socket.assigns.ash_scope)

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
        {:noreply, put_flash(socket, :error, "Nie udało się połączyć transakcji")}
    end
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    case Invoicing.disconnect_all_sales_invoice_transactions_manual(
           socket.assigns.invoice,
           socket.assigns.ash_scope
         ) do
      {:ok, _invoice} ->
        invoice = refresh_invoice(socket.assigns.invoice.id, socket.assigns.ash_scope)

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
  def handle_event("create_share_link", _params, socket) do
    invoice = socket.assigns.invoice
    scope = socket.assigns.ash_scope

    {:ok, url} = SalesInvoiceSharing.get_share_url_for_sales_invoice(invoice, scope)
    updated_invoice = refresh_invoice(invoice.id, scope)

    {:noreply,
     socket
     |> assign(:invoice, updated_invoice)
     |> push_event("copy-to-clipboard", %{text: url})
     |> put_flash(:info, "Link skopiowany do schowka")}
  end

  defp submit_cancellation_correction(socket, correction) do
    case Ksef.submit_sales_invoice(correction.id, socket.assigns.ash_scope) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Wystawiono korektę anulującą i rozpoczęto jej wysyłkę do KSeF")
         |> push_navigate(to: Navigation.sales_invoice_summary_path(correction, socket.assigns.return_to))}

      {:error, reason} ->
        Logger.error("Failed to submit cancellation correction to KSeF",
          invoice_id: correction.id,
          error_kind: ErrorKind.classify(reason)
        )

        case Ksef.cleanup_failed_correction(correction.id, socket.assigns.ash_scope) do
          {:ok, :deleted, _original_invoice_id} ->
            {:noreply, put_flash(socket, :error, Ksef.failed_correction_message(reason))}

          {:error, cleanup_error} ->
            Logger.error("Failed to clean up cancellation correction",
              invoice_id: correction.id,
              error_kind: ErrorKind.classify(cleanup_error)
            )

            {:noreply, put_flash(socket, :error, "Nie udało się wysłać korekty anulującej do KSeF")}

          cleanup_result ->
            Logger.error(
              "Unexpected cleanup result for cancellation correction invoice #{correction.id} (kind=#{ErrorKind.classify(cleanup_result)})"
            )

            {:noreply, put_flash(socket, :error, "Nie udało się wysłać korekty anulującej do KSeF")}
        end
    end
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
    _ = event
    {:noreply, socket}
  end

  defp ksef_status_flash(socket, :submitted), do: put_flash(socket, :info, "Faktura została wysłana do KSeF")

  defp ksef_status_flash(socket, :failed), do: put_flash(socket, :error, "Wysyłka do KSeF nie powiodła się")

  defp ksef_status_flash(socket, _status), do: socket
end
