defmodule FirmowidWeb.InvoicingLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.Finances
  alias Firmowid.CostInvoices
  alias Firmowid.SalesInvoices
  alias Firmowid.Invoicing

  @impl true
  def mount(params, _session, socket) do
    id = params["id"]
    action = socket.assigns.live_action

    current_user = socket.assigns.current_user

    details =
      get_invoice_details(id, current_user, action)

    socket =
      socket
      |> assign(:is_cost_invoice, action == :cost_invoice)
      |> assign(:invoice, details.invoice)
      |> assign(:potential_transactions, details.potential_transactions)
      |> assign(:is_freeform_matching, details.recommended_combo != nil)
      |> assign(:search_term, "")
      |> assign(:did_suggest_combo, details.recommended_combo != nil)
      |> assign(
        :selected_transaction_ids,
        if details.recommended_combo == nil do
          []
        else
          details.recommended_combo |> Enum.map(& &1.id)
        end
      )
      |> assign(
        :search_results,
        if details.potential_transactions == [] do
          if details.recommended_combo == nil do
            Finances.search_transactions("")
          else
            details.recommended_combo
          end
        else
          details.potential_transactions
        end
      )
      |> assign(:preview_url, details.preview_url)
      |> assign(:preview_type, details.preview_type)

      # styling
      |> assign(:no_padding, true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      id="invoicing-show"
      module={FirmowidWeb.Components.Invoicing.InvoiceDetails}
      invoice={@invoice}
      is_cost_invoice={@is_cost_invoice}
      preview_url={@preview_url}
      preview_type={@preview_type}
      show_vat_for_sales_invoice={@current_org.is_vat_payer}
      potential_transactions={@potential_transactions}
      is_freeform_matching={@is_freeform_matching}
      selected_transaction_ids={@selected_transaction_ids}
      search_term={@search_term}
      search_results={@search_results}
      did_suggest_combo={@did_suggest_combo}
    />
    """
  end

  defp get_invoice_details(id, current_user, :cost_invoice),
    do: get_cost_invoice_details(id, current_user)

  defp get_invoice_details(id, current_user, :sales_invoice),
    do: get_sales_invoice_details(id, current_user)

  defp get_sales_invoice_details(id, current_user) do
    sales_invoice = SalesInvoices.get_sales_invoice(id)

    sales_invoice_description =
      case length(sales_invoice.sales_invoice_items) do
        0 ->
          ""

        _ ->
          sales_invoice.sales_invoice_items
          |> Enum.at(0)
          |> Map.get(:name)
      end

    Bodyguard.permit!(SalesInvoices, :show, current_user, sales_invoice)

    potential_transactions = Invoicing.get_potential_transactions_for_invoice(sales_invoice)

    recommended_combo =
      Invoicing.match_with_transaction_combo(
        sales_invoice.issue_date,
        sales_invoice.due_date,
        SalesInvoices.SalesInvoice.get_gross_value(sales_invoice)
      )

    preview_url = ""
    preview_type = :html

    sales_invoice = SalesInvoices.get_sales_invoice_with_logo_url(id)

    %{
      invoice:
        Map.merge(
          sales_invoice,
          %{
            total_amount: SalesInvoices.SalesInvoice.get_gross_value(sales_invoice),
            invoice_identifier: sales_invoice.invoice_number,
            seller: sales_invoice.seller_display_name,
            description: sales_invoice_description
          }
        ),
      preview_url: preview_url,
      preview_type: preview_type,
      potential_transactions:
        if recommended_combo == nil do
          potential_transactions
        else
          recommended_combo
        end,
      recommended_combo: recommended_combo
    }
  end

  defp get_cost_invoice_details(id, current_user) do
    cost_invoice = CostInvoices.get_cost_invoice!(id)

    Bodyguard.permit!(CostInvoices, :show, current_user, cost_invoice)

    potential_transactions = Invoicing.get_potential_transactions_for_invoice(cost_invoice)

    recommended_combo =
      Invoicing.match_with_transaction_combo(
        cost_invoice.issue_date,
        cost_invoice.due_date,
        cost_invoice.total_amount
      )

    cost_invoice = CostInvoices.get_cost_invoice_with_blob_url!(id)

    %{
      invoice: cost_invoice,
      preview_url: cost_invoice.blob_url,
      preview_type:
        if String.contains?(cost_invoice.blob.blob_path, ".pdf") do
          :pdf
        else
          :image
        end,
      potential_transactions:
        if recommended_combo == nil do
          potential_transactions
        else
          recommended_combo
        end,
      recommended_combo: recommended_combo
    }
  end

  @impl true
  def handle_event("toggle-invoicing", _params, socket) do
    invoice =
      if socket.assigns.is_cost_invoice do
        toggle_cost_invoice_invoicing(socket)
      else
        toggle_sales_invoice_invoicing(socket)
      end

    socket = socket |> assign(:invoice, invoice)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", _, socket) do
    if socket.assigns.is_cost_invoice do
      Bodyguard.permit!(CostInvoices, :delete, socket.assigns.current_user)
      CostInvoices.delete_cost_invoice(socket.assigns.invoice.id)
    else
      Bodyguard.permit!(SalesInvoices, :delete, socket.assigns.current_user)
      SalesInvoices.delete_sales_invoice(socket.assigns.invoice)
    end

    socket =
      socket
      |> put_flash(:info, "Faktura została usunięta")
      |> push_navigate(to: ~p"/?month=#{socket.assigns.invoice.issue_date |> Date.to_iso8601()}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("connect", %{"transaction_id" => transaction_id}, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id
    invoice_id = socket.assigns.invoice.id

    invoice =
      if socket.assigns.is_cost_invoice do
        connect_cost_invoice(
          invoice_id,
          transaction_id,
          user,
          organization_id
        )
      else
        connect_sales_invoice(
          invoice_id,
          transaction_id,
          user,
          organization_id
        )
      end

    socket =
      socket
      |> assign(:invoice, invoice)

    {:noreply, socket}
  end

  def handle_event("connect-selected-transactions", _, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id
    invoice_id = socket.assigns.invoice.id

    [invoice | _] =
      socket.assigns.selected_transaction_ids
      |> Enum.map(fn transaction_id ->
        if socket.assigns.is_cost_invoice do
          connect_cost_invoice(
            invoice_id,
            transaction_id,
            user,
            organization_id
          )
        else
          connect_sales_invoice(
            invoice_id,
            transaction_id,
            user,
            organization_id
          )
        end
      end)
      |> Enum.reverse()

    socket =
      socket
      |> assign(:invoice, invoice)

    {:noreply, socket}
  end

  def handle_event(
        "transaction-toggled",
        %{"transaction_id" => transaction_id, "value" => "on"},
        socket
      ) do
    socket =
      socket
      |> assign(
        :selected_transaction_ids,
        socket.assigns.selected_transaction_ids ++ [transaction_id]
      )

    {:noreply, socket}
  end

  def handle_event(
        "transaction-toggled",
        %{"transaction_id" => transaction_id},
        socket
      ) do
    socket =
      socket
      |> assign(
        :selected_transaction_ids,
        Enum.filter(socket.assigns.selected_transaction_ids, fn id -> id != transaction_id end)
      )

    {:noreply, socket}
  end

  def handle_event("disconnect", _, socket) do
    user = socket.assigns.current_user

    invoice =
      if socket.assigns.is_cost_invoice do
        Bodyguard.permit!(CostInvoices, :update, user)
        CostInvoices.delete_cost_invoices_transactions_connections(socket.assigns.invoice.id)

        CostInvoices.get_cost_invoice_with_blob_url!(socket.assigns.invoice.id)
      else
        Bodyguard.permit!(SalesInvoices, :update, user)
        SalesInvoices.delete_sales_invoices_transactions_connections(socket.assigns.invoice.id)

        details = get_sales_invoice_details(socket.assigns.invoice.id, user)
        details.invoice
      end

    socket =
      socket
      |> assign(:invoice, invoice)

    {:noreply, socket}
  end

  def handle_event("search", %{"search-term" => ""}, socket) do
    socket =
      socket
      |> assign(:search_term, "")
      |> assign(
        :search_results,
        socket.assigns.selected_transaction_ids
        |> Enum.map(fn id -> Finances.get_transaction!(id) end)
      )

    {:noreply, socket}
  end

  def handle_event("search", %{"search-term" => search_term}, socket) do
    socket =
      socket
      |> assign(:search_term, search_term)
      |> assign(:search_results, Finances.search_transactions(search_term))

    {:noreply, socket}
  end

  def handle_event("toggle-freeform", _, socket) do
    socket =
      socket
      |> assign(:is_freeform_matching, !socket.assigns.is_freeform_matching)

    {:noreply, socket}
  end

  defp connect_cost_invoice(invoice_id, transaction_id, user, organization_id) do
    Bodyguard.permit!(CostInvoices, :update, user)

    CostInvoices.create_cost_invoices_transactions_connection(
      invoice_id,
      transaction_id,
      organization_id
    )

    CostInvoices.get_cost_invoice_with_blob_url!(invoice_id)
  end

  defp toggle_cost_invoice_invoicing(socket) do
    Bodyguard.permit!(CostInvoices, :update, socket.assigns.current_user)

    CostInvoices.toggle_skip_invoicing(socket.assigns.invoice.id)
  end

  defp connect_sales_invoice(invoice_id, transaction_id, user, organization_id) do
    Bodyguard.permit!(SalesInvoices, :update, user)

    SalesInvoices.create_sales_invoices_transactions_connection(
      invoice_id,
      transaction_id,
      organization_id
    )

    details = get_sales_invoice_details(invoice_id, user)

    details.invoice
  end

  defp toggle_sales_invoice_invoicing(socket) do
    Bodyguard.permit!(SalesInvoices, :update, socket.assigns.current_user)

    SalesInvoices.toggle_skip_invoicing(socket.assigns.invoice.id)

    details = get_sales_invoice_details(socket.assigns.invoice.id, socket.assigns.current_user)

    details.invoice
  end
end
