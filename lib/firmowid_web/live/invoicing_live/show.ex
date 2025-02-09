defmodule FirmowidWeb.InvoicingLive.Show do
  use FirmowidWeb, :live_view

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
      |> assign(:grouped_potential_transactions, details.grouped_potential_transactions)
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
      potential_transactions={@potential_transactions}
      grouped_potential_transactions={@grouped_potential_transactions}
    />
    """
  end

  defp get_invoice_details(id, current_user, :cost_invoice),
    do: get_cost_invoice_details(id, current_user)

  defp get_invoice_details(id, current_user, :sales_invoice),
    do: get_sales_invoice_details(id, current_user)

  defp get_sales_invoice_details(id, current_user) do
    sales_invoice = SalesInvoices.get_sales_invoice(id)

    Bodyguard.permit!(SalesInvoices, :show, current_user, sales_invoice)

    potential_transactions = []
    grouped_potential_transactions = []

    preview_url = ""
    preview_type = :html

    %{
      invoice:
        Map.merge(
          sales_invoice,
          %{
            total_amount: SalesInvoices.SalesInvoice.get_gross_value(sales_invoice),
            invoice_identifier: sales_invoice.invoice_number,
            seller: sales_invoice.seller_display_name,
            description: nil
          }
        ),
      preview_url: preview_url,
      preview_type: preview_type,
      potential_transactions: potential_transactions,
      grouped_potential_transactions: grouped_potential_transactions
    }
  end

  defp get_cost_invoice_details(id, current_user) do
    cost_invoice = CostInvoices.get_cost_invoice!(id)

    Bodyguard.permit!(CostInvoices, :show, current_user, cost_invoice)

    potential_transactions =
      if cost_invoice.transactions == [] do
        potential_transactions =
          Invoicing.get_potential_transactions_for_cost_invoice(
            cost_invoice,
            similarity_threshold: 0.0,
            days_before: 15,
            days_after: 10,
            exact_amount: false
          )
          |> Enum.map(fn t ->
            Map.merge(t, %{
              amount:
                Money.new(
                  t.transaction_currency,
                  t.transaction_amount
                )
            })
          end)

        Invoicing.llm_re_grade_matches(
          cost_invoice,
          potential_transactions
        )
        |> Enum.map(fn {transaction, grade} -> Map.put(transaction, :llm_eval, grade) end)
        |> Enum.sort_by(& &1.llm_eval, :desc)
      else
        []
      end

    is_llm_certain = Enum.all?(potential_transactions, fn t -> t.llm_eval > 0.9 end)

    grouped_potential_transactions =
      if cost_invoice.transactions == [] and
           (potential_transactions == [] or
              not is_llm_certain) do
        Invoicing.match_with_transaction_combo(cost_invoice)
      else
        []
      end

    %{
      invoice: cost_invoice,
      preview_url: cost_invoice.blob_url,
      preview_type:
        if String.contains?(cost_invoice.blob.blob_path, ".pdf") do
          :pdf
        else
          :image
        end,
      potential_transactions: potential_transactions,
      grouped_potential_transactions: grouped_potential_transactions
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
      end

    socket =
      socket
      |> assign(:invoice, invoice)

    {:noreply, socket}
  end

  def handle_event("disconnect", _, socket) do
    user = socket.assigns.current_user

    invoice =
      if socket.assigns.is_cost_invoice do
        Bodyguard.permit!(CostInvoices, :update, user)
        CostInvoices.delete_cost_invoices_transactions_connections(socket.assigns.invoice.id)

        CostInvoices.get_cost_invoice!(socket.assigns.invoice.id)
      end

    socket =
      socket
      |> assign(:invoice, invoice)

    {:noreply, socket}
  end

  defp connect_cost_invoice(invoice_id, transaction_id, user, organization_id) do
    Bodyguard.permit!(CostInvoices, :update, user)

    CostInvoices.create_cost_invoices_transactions_connection(
      invoice_id,
      transaction_id,
      organization_id
    )

    CostInvoices.get_cost_invoice!(invoice_id)
  end

  defp toggle_cost_invoice_invoicing(socket) do
    Bodyguard.permit!(CostInvoices, :update, socket.assigns.current_user)

    CostInvoices.toggle_skip_invoicing(socket.assigns.invoice.id)
  end

  defp toggle_sales_invoice_invoicing(socket) do
    Bodyguard.permit!(SalesInvoices, :update, socket.assigns.current_user)

    SalesInvoices.toggle_skip_invoicing(socket.assigns.invoice.id)

    details = get_sales_invoice_details(socket.assigns.invoice.id, socket.assigns.current_user)
    details.invoice
  end
end
