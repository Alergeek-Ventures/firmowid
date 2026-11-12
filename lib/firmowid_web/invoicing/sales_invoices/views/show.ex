defmodule FirmowidWeb.Invoicing.SalesInvoices.Views.Show do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Ash.Notifier.Notification
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Calculations.AnnotatedCorrections
  alias Firmowid.Invoicing.FailureReporter
  alias Firmowid.Invoicing.InvoiceMatching
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.Services.SalesInvoiceSharing
  alias Firmowid.Ksef
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias Phoenix.Socket.Broadcast

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
      potential_transactions =
        InvoiceMatching.get_potential_transactions_for_invoice(sales_invoice, scope)

      sales_invoice =
        then(sales_invoice, fn inv -> %{inv | corrections: AnnotatedCorrections.annotate(inv)} end)

      logo_url = Invoicing.get_logo_url(sales_invoice.organization_id, scope: scope)

      # Subscribe to KSeF status updates for live feedback
      Ksef.subscribe_ksef_status(current_user.member.organization_id)

      if connected?(socket),
        do: Endpoint.subscribe("sales_invoice:updated:#{current_user.member.organization_id}")

      socket =
        socket
        |> assign(:invoice, sales_invoice)
        |> assign(:logo_url, logo_url)
        |> assign(:potential_transactions, potential_transactions)
        |> assign(:preview_url, "")
        |> assign(:preview_type, :html)
        |> assign(:no_padding, true)
        |> assign(:page_title, gettext("Sales invoice"))
        |> assign(:return_to, return_to)

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
      scope={@ash_scope}
      feature_flags={@feature_flags}
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
    {:noreply, put_flash(socket, :error, gettext("Could not generate the PDF."))}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case SalesInvoice.destroy(socket.assigns.invoice, scope: socket.assigns.ash_scope) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("The invoice has been deleted."))
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
           gettext("An invoice sent to KSeF cannot be deleted. Issue a correction invoice.")
         )}
    end
  end

  @impl true
  def handle_event("cancel", %{"correction_reason" => correction_reason} = params, socket) do
    arguments = %{
      correction_reason: correction_reason,
      confirm_corrected_buyer_vat_id: params["confirm_corrected_buyer_vat_id"] == "true"
    }

    case SalesInvoice.cancel(socket.assigns.invoice.id, arguments, scope: socket.assigns.ash_scope) do
      {:ok, correction} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("A cancelling correction was issued and its submission to KSeF has started.")
         )
         |> push_navigate(to: Navigation.sales_invoice_summary_path(correction, socket.assigns.return_to))}

      {:error, %Ash.Error.Invalid{errors: [%{message: message} = error | _rest]} = invalid}
      when is_binary(message) ->
        FailureReporter.report(
          invalid,
          :cancel,
          socket.assigns.ash_scope.tenant,
          socket.assigns.invoice.id
        )

        {:noreply, put_flash(socket, :error, Inputs.translate_error({message, Map.get(error, :vars, [])}))}

      {:error, error} ->
        raise error
    end
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => tx_id}, socket) do
    case Invoicing.connect_sales_invoice_transactions(socket.assigns.invoice, [tx_id], scope: socket.assigns.ash_scope) do
      {:ok, _connected_invoice} ->
        {:noreply, assign_refreshed_invoice(socket)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not link the transaction."))}
    end
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    case Invoicing.disconnect_all_sales_invoice_transactions(socket.assigns.invoice,
           scope: socket.assigns.ash_scope
         ) do
      {:ok, _invoice} ->
        {:noreply, assign_refreshed_invoice(socket)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not unlink the transaction."))}
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
     |> put_flash(:info, gettext("Link copied to the clipboard."))}
  end

  defp assign_refreshed_invoice(socket) do
    scope = socket.assigns.ash_scope
    invoice = refresh_invoice(socket.assigns.invoice.id, scope)

    assign(socket,
      invoice: invoice,
      potential_transactions: InvoiceMatching.get_potential_transactions_for_invoice(invoice, scope)
    )
  end

  defp refresh_invoice(id, scope) do
    invoice = Invoicing.get_sales_invoice!(id, load: @detail_loads, scope: scope)
    %{invoice | corrections: AnnotatedCorrections.annotate(invoice)}
  end

  @impl true
  def handle_info(
        %Broadcast{payload: %Notification{resource: SalesInvoice, data: %{id: id}, action: %{name: action}}},
        %{assigns: %{invoice: %{id: id}}} = socket
      )
      when action in [:connect_transactions, :disconnect_transactions, :disconnect_all_transactions] do
    {:noreply, assign_refreshed_invoice(socket)}
  end

  def handle_info({:ksef_invoice_status, %{invoice_id: invoice_id, status: status}}, socket) do
    # Handle KSeF submission status updates
    if socket.assigns.invoice.id == invoice_id do
      invoice = refresh_invoice(invoice_id, socket.assigns.ash_scope)

      socket =
        socket
        |> assign(:invoice, invoice)
        |> ksef_status_flash(status)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp ksef_status_flash(socket, :submitted), do: put_flash(socket, :info, gettext("The invoice was sent to KSeF."))

  defp ksef_status_flash(socket, :failed), do: put_flash(socket, :error, gettext("Sending to KSeF failed."))

  defp ksef_status_flash(socket, _status), do: socket
end
