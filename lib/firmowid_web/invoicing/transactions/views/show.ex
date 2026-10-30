defmodule FirmowidWeb.Invoicing.Transactions.Views.Show do
  @moduledoc """
  Transaction details page with source account information and invoice matching.
  """

  use FirmowidWeb, :live_view

  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Ash.Notifier.Notification
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.InvoiceMatching
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Payroll
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Invoicing.Components.InvoiceDetails
  alias FirmowidWeb.Invoicing.Transactions.Components.SalaryComponents
  alias FirmowidWeb.Invoicing.Transactions.Components.ShowComponents
  alias FirmowidWeb.Invoicing.Utilities.Navigation
  alias Phoenix.Socket.Broadcast

  @transaction_loads [
    :bank_account,
    :direction,
    :signed_amount,
    :has_salary?,
    :reconciliation_status,
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
    if connected?(socket) do
      organization_id = socket.assigns.current_org.id
      Endpoint.subscribe("transaction:updated:#{organization_id}")
      Endpoint.subscribe("sales_invoice:updated:#{organization_id}")
      Endpoint.subscribe("cost_invoice:updated:#{organization_id}")
    end

    {:ok,
     socket
     |> assign(:no_padding, true)
     |> assign(:page_title, gettext("Transaction"))
     |> assign(:return_to, nil)
     |> assign(:salary_admin?, socket.assigns.current_user.member.role == :admin)}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _url, socket) do
    scope = socket.assigns.ash_scope
    transaction = reload_transaction(id, scope)
    return_to = Navigation.return_to_path(params["powrot_do"])

    {:noreply,
     socket
     |> assign(:return_to, return_to)
     |> assign_transaction(transaction)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="transaction-show" class="flex flex-col">
      <ShowComponents.header transaction={@transaction} return_to={@return_to} />

      <div class="flex min-w-0 flex-col bg-white lg:flex-row">
        <ShowComponents.details_sidebar
          transaction={@transaction}
          can_write={Ash.can?({Transaction, :update_internal_note}, @current_user)}
        />

        <InvoiceDetails.main>
          <.live_component
            :if={
              flag_enabled?(:analysis_dashboard, assigns) and not @transaction.has_salary? and
                @transaction.reconciliation_status in [:matched, :skipped]
            }
            module={FirmowidWeb.Analysis.Components.EntryCategories}
            id="transaction-categories"
            entry={@transaction}
            scope={@ash_scope}
            feature_flags={@feature_flags}
          />
          <%= cond do %>
            <% @transaction.has_salary? -> %>
              <SalaryComponents.confirmation
                transaction={@transaction}
                expected_amount={@expected_salary_amount}
                payout_variant={@salary_payout_variant}
                admin?={@salary_admin?}
              />
            <% @transaction.reconciliation_status == :skipped -> %>
              <ShowComponents.transaction_skipped_view can_write={
                Ash.can?({Transaction, :set_skip_invoicing}, @current_user)
              } />
            <% @transaction.reconciliation_status == :matched -> %>
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
  def handle_event("save_internal_note", %{"internal_note" => note}, socket) do
    transaction =
      Transaction.update_internal_note!(socket.assigns.transaction, note, scope: socket.assigns.ash_scope)

    {:noreply,
     assign(socket, :transaction, %{
       socket.assigns.transaction
       | internal_note: transaction.internal_note
     })}
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

    result = Invoicing.disconnect_transaction_from_all_invoices(transaction, scope)

    case result do
      {:ok, _transaction} ->
        {:noreply, assign_transaction(socket, reload_transaction(transaction.id, scope))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to unlink the invoices"))}
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
        {:noreply, put_flash(socket, :error, gettext("Could not link this transaction to the invoice."))}
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
        {:noreply, assign_transaction(socket, reload_transaction(transaction.id, socket.assigns.ash_scope))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not link this transaction to a salary."))}
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
           gettext("Could not unlink this transaction from the salary.")
         )}
    end
  end

  @impl true
  def handle_info(
        %Broadcast{payload: %Notification{resource: Transaction, data: %{id: id}}},
        %{assigns: %{transaction: %{id: id}}} = socket
      ) do
    {:noreply, assign_transaction(socket, reload_transaction(id, socket.assigns.ash_scope))}
  end

  def handle_info(%Broadcast{payload: %Notification{resource: resource, action: %{name: action}}}, socket)
      when resource in [SalesInvoice, CostInvoice] and
             action in [:connect_transactions, :disconnect_transactions, :disconnect_all_transactions] do
    {:noreply,
     assign_transaction(
       socket,
       reload_transaction(socket.assigns.transaction.id, socket.assigns.ash_scope)
     )}
  end

  def handle_info(%Broadcast{}, socket), do: {:noreply, socket}

  defp connect_invoice_transaction(%CostInvoice{} = invoice, transaction_id, scope) do
    Invoicing.connect_cost_invoice_transactions(invoice, [transaction_id], scope: scope)
  end

  defp connect_invoice_transaction(%SalesInvoice{} = invoice, transaction_id, scope) do
    Invoicing.connect_sales_invoice_transactions(invoice, [transaction_id], scope: scope)
  end

  defp reload_transaction(id, scope) do
    Finances.get_transaction!(id,
      load: [{:salary_user, :member} | @transaction_loads],
      scope: scope
    )
  end

  defp assign_transaction(socket, transaction) do
    scope = socket.assigns.ash_scope

    estimate =
      if socket.assigns.salary_admin? and transaction.has_salary? do
        salary =
          %{
            user_id: transaction.salary_user_id,
            active_at: Date.end_of_month(transaction.salary_month)
          }
          |> Payroll.list_salaries!(
            load: [
              monthly_amount: [month: transaction.salary_month],
              payout_estimates: [month: transaction.salary_month]
            ],
            scope: scope
          )
          |> List.first()

        if salary do
          Firmowid.Payroll.UserSalary.Calculations.PayoutEstimates.closest(
            salary.payout_estimates,
            transaction.amount
          ) ||
            %{amount: salary.monthly_amount, variant: nil}
        end
      end

    salary_suggestions =
      if socket.assigns.salary_admin? do
        Finances.suggest_transaction_salaries!(transaction.id, scope: scope).suggestions
      else
        []
      end

    socket
    |> assign(:transaction, transaction)
    |> assign(:expected_salary_amount, if(estimate, do: estimate.amount))
    |> assign(:salary_payout_variant, if(estimate, do: estimate.variant))
    |> assign(
      :invoice_suggestions,
      InvoiceMatching.get_potential_invoices_for_transaction(transaction, scope)
    )
    |> assign(:salary_suggestions, salary_suggestions)
  end
end
