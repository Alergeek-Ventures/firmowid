defmodule FirmowidWeb.CostInvoicesLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.CostInvoices
  alias Firmowid.Invoicing

  @impl true
  def mount(params, _session, socket) do
    cost_invoice = CostInvoices.get_cost_invoice!(params["id"])

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
        |> Enum.map(fn {t, grade} -> Map.put(t, :llm_eval, grade) end)
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

    socket =
      socket
      |> assign(:cost_invoice, cost_invoice)
      |> assign(:potential_transactions, potential_transactions)
      |> assign(:grouped_potential_transactions, grouped_potential_transactions)

      # styling
      |> assign(:no_padding, true)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "connect-group",
        %{"group-id" => group_id},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    cost_invoice_id = socket.assigns.cost_invoice.id

    grouped_potential_transactions = socket.assigns.grouped_potential_transactions

    {_group, transactions} =
      Enum.find(grouped_potential_transactions, fn {group, _} -> group.id == group_id end)

    transactions
    |> Enum.map(fn t ->
      CostInvoices.create_cost_invoices_transactions_connection(
        cost_invoice_id,
        t.id,
        organization_id
      )
    end)

    cost_invoice = CostInvoices.get_cost_invoice!(cost_invoice_id)

    socket =
      socket
      |> assign(:cost_invoice, cost_invoice)
      |> assign(:grouped_potential_transactions, [])
      |> assign(:potential_transactions, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "connect",
        %{
          "cost-invoice-id" => cost_invoice_id,
          "transaction-id" => transaction_id
        },
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    CostInvoices.create_cost_invoices_transactions_connection(
      cost_invoice_id,
      transaction_id,
      organization_id
    )

    cost_invoice = CostInvoices.get_cost_invoice!(cost_invoice_id)

    socket =
      socket
      |> assign(:cost_invoice, cost_invoice)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "disconnect",
        %{
          "cost-invoice-id" => cost_invoice_id,
          "transaction-id" => transaction_id
        },
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    CostInvoices.delete_cost_invoices_transactions_connection(
      organization_id,
      cost_invoice_id,
      transaction_id
    )

    cost_invoice = CostInvoices.get_cost_invoice!(cost_invoice_id)

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

    potential_transactions =
      Invoicing.llm_re_grade_matches(
        cost_invoice,
        potential_transactions
      )
      |> Enum.map(fn {t, grade} -> Map.put(t, :llm_eval, grade) end)
      |> Enum.sort_by(& &1.llm_eval, :desc)

    socket =
      socket
      |> assign(:cost_invoice, cost_invoice)
      |> assign(:potential_transactions, potential_transactions)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "disconnect-group",
        %{"cost-invoice-id" => cost_invoice_id},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    cost_invoice = CostInvoices.get_cost_invoice!(cost_invoice_id)

    cost_invoice.transactions
    |> Enum.map(fn t ->
      CostInvoices.delete_cost_invoices_transactions_connection(
        organization_id,
        cost_invoice_id,
        t.id
      )
    end)

    cost_invoice = CostInvoices.get_cost_invoice!(cost_invoice_id)

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

    potential_transactions =
      Invoicing.llm_re_grade_matches(
        cost_invoice,
        potential_transactions
      )
      |> Enum.map(fn {t, grade} -> Map.put(t, :llm_eval, grade) end)
      |> Enum.sort_by(& &1.llm_eval, :desc)

    grouped_potential_transactions =
      if cost_invoice.transactions == [] and potential_transactions == [] do
        Invoicing.match_with_transaction_combo(cost_invoice)
      else
        []
      end

    socket =
      socket
      |> assign(:cost_invoice, cost_invoice)
      |> assign(:potential_transactions, potential_transactions)
      |> assign(:grouped_potential_transactions, grouped_potential_transactions)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-skip-invoicing", _, socket) do
    cost_invoice =
      CostInvoices.toggle_skip_invoicing(
        :cost_invoice,
        socket.assigns.cost_invoice.id
      )

    socket =
      socket
      |> assign(:cost_invoice, cost_invoice)

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"cost-invoice-id" => cost_invoice_id}, socket) do
    cost_invoice = CostInvoices.get_cost_invoice!(cost_invoice_id)

    CostInvoices.delete_cost_invoice(cost_invoice_id)

    LiveToast.send_toast(
      :info,
      "Dokument został usunięty."
    )

    socket =
      socket
      |> push_navigate(to: ~p"/?month=#{cost_invoice.issue_date |> Date.to_iso8601()}")

    {:noreply, socket}
  end

  defp apply_action(socket, :index, params) do
    cost_invoice = CostInvoices.get_cost_invoice!(params["id"])

    socket
    |> assign(
      :page_title,
      "Podgląd dokumentu #{cost_invoice.invoice_identifier} od #{cost_invoice.seller_display_name}"
    )
  end
end
