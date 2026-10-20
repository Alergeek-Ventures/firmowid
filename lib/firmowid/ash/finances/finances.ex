defmodule Firmowid.Ash.Finances do
  @moduledoc """
  Ash domain for bank accounts and transactions.

  Manages bank account CRUD, transaction synchronization from bank APIs,
  transaction search (ParadeDB), and invoicing-related transaction queries.
  """
  use Ash.Domain, extensions: [AshAi]

  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Scope

  require Ash.Query

  tools do
    tool :list_transactions, Transaction, :list do
      annotations title: "List bank transactions",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "List the organization's synced bank transactions to find payments, answer questions and match " <>
                    "them with invoices or salaries. Amounts are signed: income positive, expenses negative; " <>
                    "direction tells which. reconciliation_status pending means unresolved, matched means linked to " <>
                    "an invoice or a salary, skipped means excluded from matching. Use after/before keyset cursors " <>
                    "with the same filters to navigate pages."

      action_parameters [:sort, :limit]

      select [
        :id,
        :booking_date,
        :amount,
        :creditor_name,
        :debtor_name,
        :remittance_information_unstructured,
        :salary_user_id,
        :salary_month
      ]

      load [:direction, :counterparty_display_name, :reconciliation_status]
    end

    tool :suggest_transaction_invoices, Transaction, :invoice_suggestions do
      annotations title: "Suggest invoices for a transaction",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Rank unresolved invoices that a pending bank transaction may pay, using the same model as " <>
                    "automatic matching: sales invoices for income, cost invoices for expenses, best score first. " <>
                    "Returns nothing for a matched or skipped transaction. The score only ranks candidates; confirm " <>
                    "the counterparty, amount and title before proposing a match. Changes nothing."
    end

    tool :suggest_transaction_salaries, Transaction, :salary_suggestions do
      annotations title: "Suggest salaries for a transfer",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Suggest which employee's monthly salary a pending outgoing PLN transfer pays. Considers months " <>
                    "with logged time up to six months back whose salary is not yet assigned and whose amount is " <>
                    "within 20% (at least 300 PLN) of the transfer, ranked by the recipient's name, the expected " <>
                    "month and the amount difference. By default only salaries with a submitted hours record count. " <>
                    "Requires an administrator. Changes nothing."
    end

    tool :connect_transaction_salary, Transaction, :connect_salary do
      annotations title: "Assign transfer to salary",
                  read_only_hint: false,
                  destructive_hint: false,
                  open_world_hint: false

      description "Settle one employee's monthly salary with a pending outgoing transfer, only after the user " <>
                    "approves the specific match. Pass salary_user_id and salary_month (first day of the month) " <>
                    "from suggest_transaction_salaries. A salary month can be paid by one transfer only, and a " <>
                    "transfer connected to an invoice cannot be assigned. Requires an administrator."

      select [:id, :booking_date, :amount, :salary_user_id, :salary_month]
      load [:reconciliation_status]
    end

    tool :disconnect_transaction_salary, Transaction, :disconnect_salary do
      annotations title: "Unassign transfer from salary",
                  read_only_hint: false,
                  destructive_hint: true,
                  idempotent_hint: true,
                  open_world_hint: false

      description "Remove a wrong salary assignment from a transfer when the user asks. The bank transaction stays " <>
                    "and becomes pending again. Requires an administrator."

      select [:id, :booking_date, :amount, :salary_user_id, :salary_month]
      load [:reconciliation_status]
    end
  end

  resources do
    resource BankAccount do
      define :get_bank_account, action: :read, get_by: [:id]
      define :list_bank_accounts, action: :read
      define :sync_bank_account, action: :sync_from_bank
      define :create_manual_bank_account, action: :create_manual
      define :update_bank_account, action: :update
      define :clear_bank_account_default, action: :clear_default
      define :destroy_bank_account, action: :destroy
      define :list_bank_accounts_for_sync, action: :read_global_for_sync
    end

    resource Firmowid.Ash.Finances.Institution do
      define :list_institutions, action: :for_country, args: [:country]
    end

    resource Firmowid.Ash.Finances.Requisition do
      define :create_requisition,
        action: :create_requisition,
        args: [:institution_id, :max_transaction_days, :redirect_url]

      define :get_requisition, action: :read, get_by: [:id]
      define :list_requisitions, action: :list
    end

    resource Transaction do
      define :get_transaction, action: :read, get_by: [:id]
      define :list_transactions, action: :list
      define :upsert_transaction_from_sync, action: :upsert_from_sync
      define :set_transaction_skip_invoicing, action: :set_skip_invoicing
      define :connect_transaction_salary, action: :connect_salary
      define :disconnect_transaction_salary, action: :disconnect_salary
      define :suggest_transaction_salaries, action: :salary_suggestions, args: [:transaction_id]
      define :suggest_transaction_invoices, action: :invoice_suggestions, args: [:transaction_id]
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Returns the default bank account for the given currency within the current scope.
  """
  @spec get_default_bank_account_for_currency(String.t(), Scope.t()) ::
          {:ok, BankAccount.t() | nil} | {:error, term()}
  def get_default_bank_account_for_currency(currency, %Scope{} = scope) do
    %{}
    |> query_to_list_bank_accounts(scope: scope)
    |> Ash.Query.filter(is_default == true and currency == ^currency)
    |> Ash.Query.select([:id, :iban, :currency, :is_default])
    |> Ash.read_one(scope: scope)
  end
end
