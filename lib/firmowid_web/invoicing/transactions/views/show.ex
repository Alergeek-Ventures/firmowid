defmodule FirmowidWeb.Invoicing.Transactions.Views.Show do
  @moduledoc """
  Transaction details page with source account information and assistant access.
  """

  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.InvoiceMatching
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Payroll.SalaryMatching
  alias FirmowidWeb.Invoicing.Assistant.Utilities.SessionCloser
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Transactions.Components.SalaryComponents
  alias FirmowidWeb.Invoicing.Transactions.Components.ShowComponents
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  @transaction_loads [
    :bank_account,
    :direction,
    :signed_amount,
    :has_salary?,
    :counterparty_display_name,
    cost_invoices: [
      :invoice_source,
      :effective_amount,
      :effective_seller_display_name,
      :issue_date,
      :invoice_identifier
    ],
    sales_invoices: [
      :amount,
      :buyer_display_name_label,
      :issue_date,
      :invoice_number,
      sales_invoice_items: [:name]
    ]
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:chat, false)
     |> assign(:no_padding, true)
     |> assign(:return_to, nil)
     |> assign(:salary_admin?, socket.assigns.current_user.role == :admin)}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    scope = socket.assigns.ash_scope
    transaction = reload_transaction(id, scope)
    return_to = Navigation.return_to_path(params["powrot_do"])

    {:noreply,
     socket
     |> maybe_reset_chat(id)
     |> assign(:return_to, return_to)
     |> assign_transaction(transaction)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="transaction-show" class="flex flex-col">
      <ShowComponents.header transaction={@transaction} return_to={@return_to} />

      <div class="flex min-w-0 flex-col bg-white lg:flex-row">
        <ShowComponents.details_sidebar transaction={@transaction} />

        <InvoiceDetails.main>
          <%= cond do %>
            <% @transaction.has_salary? -> %>
              <SalaryComponents.confirmation
                transaction={@transaction}
                summary={@salary_summary}
                admin?={@salary_admin?}
              />
            <% @chat -> %>
              <ShowComponents.assistant_state
                transaction={@transaction}
                current_user={@current_user}
                scope={@ash_scope}
                return_to={@return_to}
              />
            <% @transaction.skip_invoicing -> %>
              <ShowComponents.transaction_skipped_view can_write={
                Ash.can?({Transaction, :set_skip_invoicing}, @current_user)
              } />
            <% linked_invoices?(@transaction) -> %>
              <ShowComponents.linked_state transaction={@transaction} return_to={@return_to} />
            <% true -> %>
              <div class="flex flex-col gap-18">
                <ShowComponents.invoice_suggestions suggestions={@invoice_suggestions} />
                <SalaryComponents.suggestions suggestions={@salary_suggestions} />
                <ShowComponents.empty_state
                  transaction={@transaction}
                  can_write={Ash.can?({Transaction, :set_skip_invoicing}, @current_user)}
                  show_no_recommendations={@invoice_suggestions == [] and @salary_suggestions == []}
                />
              </div>
          <% end %>
        </InvoiceDetails.main>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("show_chat", _params, socket) do
    {:noreply, assign(socket, :chat, true)}
  end

  def handle_event("close_chat", params, socket) do
    SessionCloser.close(params, socket.assigns.ash_scope)
    {:noreply, assign(socket, :chat, false)}
  end

  def handle_event("toggle-invoicing", _params, socket) do
    scope = socket.assigns.ash_scope
    transaction = socket.assigns.transaction

    Finances.set_transaction_skip_invoicing!(
      transaction,
      %{skip_invoicing: !transaction.skip_invoicing},
      scope: scope
    )

    {:noreply, assign_transaction(socket, reload_transaction(transaction.id, scope))}
  end

  def handle_event("unlink_all", _params, socket) do
    transaction = socket.assigns.transaction
    scope = socket.assigns.ash_scope

    result = Invoicing.disconnect_transaction_from_all_invoices_manual(transaction, scope)

    case result do
      {:ok, _transaction} ->
        {:noreply, assign_transaction(socket, reload_transaction(transaction.id, scope))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się odłączyć faktur")}
    end
  end

  def handle_event("connect_invoice", %{"invoice_id" => invoice_id}, socket) do
    result =
      case Enum.find(socket.assigns.invoice_suggestions, fn {invoice, _score} ->
             invoice.id == invoice_id
           end) do
        {invoice, _score} ->
          connect_invoice_transaction(
            invoice,
            socket.assigns.transaction.id,
            socket.assigns.ash_scope
          )

        nil ->
          {:error, :unknown_invoice}
      end

    case result do
      {:ok, _invoice} ->
        {:noreply,
         assign_transaction(
           socket,
           reload_transaction(socket.assigns.transaction.id, socket.assigns.ash_scope)
         )}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not connect this transaction to the invoice."))}
    end
  end

  def handle_event("connect_salary", %{"user_id" => user_id, "month" => month}, socket) do
    result =
      Finances.connect_transaction_salary(
        socket.assigns.transaction,
        %{salary_user_id: user_id, salary_month: month},
        scope: socket.assigns.ash_scope
      )

    case result do
      {:ok, transaction} ->
        {:noreply,
         socket
         |> assign(:chat, false)
         |> assign_transaction(reload_transaction(transaction.id, socket.assigns.ash_scope))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not connect this transaction to a salary."))}
    end
  end

  def handle_event("disconnect_salary", _params, socket) do
    case Finances.disconnect_transaction_salary(socket.assigns.transaction, %{}, scope: socket.assigns.ash_scope) do
      {:ok, transaction} ->
        {:noreply, assign_transaction(socket, reload_transaction(transaction.id, socket.assigns.ash_scope))}

      {:error, _error} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not disconnect this transaction from the salary.")
         )}
    end
  end

  defp linked_invoices?(transaction) do
    transaction.cost_invoices != [] or transaction.sales_invoices != []
  end

  defp connect_invoice_transaction(%CostInvoice{} = invoice, transaction_id, scope) do
    Invoicing.connect_cost_invoice_transactions_manual(invoice, [transaction_id], scope)
  end

  defp connect_invoice_transaction(%SalesInvoice{} = invoice, transaction_id, scope) do
    Invoicing.connect_sales_invoice_transactions_manual(invoice, [transaction_id], scope)
  end

  defp reload_transaction(id, scope) do
    loads =
      if scope.actor.role == :admin,
        do: [:salary_user | @transaction_loads],
        else: @transaction_loads

    Finances.get_transaction!(id, load: loads, scope: scope)
  end

  defp assign_transaction(socket, transaction) do
    scope = socket.assigns.ash_scope

    summary =
      if socket.assigns.salary_admin? and transaction.has_salary? do
        SalaryMatching.summary(transaction.salary_user_id, transaction.salary_month, scope)
      end

    socket
    |> assign(:transaction, transaction)
    |> assign(:salary_summary, summary)
    |> assign(
      :invoice_suggestions,
      InvoiceMatching.get_potential_invoices_for_transaction(transaction, scope)
    )
    |> assign(:salary_suggestions, SalaryMatching.suggestions(transaction, scope))
  end

  defp maybe_reset_chat(socket, id) do
    case socket.assigns[:transaction] do
      %Transaction{id: ^id} -> socket
      _ -> assign(socket, :chat, false)
    end
  end
end
