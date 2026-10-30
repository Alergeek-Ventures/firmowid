defmodule Firmowid.Finances do
  @moduledoc """
  Ash domain for bank accounts and transactions.

  Manages bank account CRUD, transaction synchronization from bank APIs,
  transaction search (ParadeDB), and invoicing-related transaction queries.
  """
  use Ash.Domain, extensions: [AshAi]

  alias Firmowid.Finances.BankAccount
  alias Firmowid.Finances.Transaction
  alias Firmowid.Scope

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
        :internal_note,
        :salary_user_id,
        :salary_month
      ]

      load [:direction, :counterparty_display_name, :reconciliation_status]
    end

    tool :update_transaction_internal_note, Transaction, :update_internal_note do
      annotations title: "Update bank transaction internal note",
                  read_only_hint: false,
                  destructive_hint: true,
                  idempotent_hint: true,
                  open_world_hint: false

      description "Replace the bank transaction's internal note only when the user asks. Pass null to clear it. " <>
                    "Maximum 10000 characters. Does not change bank data, the transfer title or invoice/salary matches. " <>
                    "Requires an accountant or administrator."

      select [:id, :internal_note]
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

    tool :restore_transaction_for_matching, Transaction, :restore_for_matching do
      annotations title: "Restore skipped transaction",
                  read_only_hint: false,
                  destructive_hint: false,
                  idempotent_hint: true,
                  open_world_hint: false

      description "Return a skipped transaction to pending so it can be connected to an invoice or a salary. " <>
                    "A pending transaction stays unchanged; a matched one returns an error naming the conflict. " <>
                    "Requires an accountant or administrator."

      select [:id, :booking_date, :amount, :salary_user_id, :salary_month]
      load [:reconciliation_status]
    end

    tool :list_monthly_salaries, Transaction, :monthly_salaries do
      annotations title: "List salaries of a month",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "List every employee salary of one month, including already paid ones and months without " <>
                    "submitted hours, with no amount or date window. expected_amount is the hourly rate multiplied " <>
                    "by the logged hours rounded up, not a recorded payout. payout_estimates contains hypothetical " <>
                    "net payout alternatives. connected_transaction_id is the transfer " <>
                    "assigned to that salary. Use it to find the right salary when suggestions miss it. Requires an " <>
                    "administrator. Changes nothing."
    end

    tool :suggest_transaction_salaries, Transaction, :salary_suggestions do
      annotations title: "Suggest salaries for a transfer",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Suggest which employee's monthly salary a pending or skipped outgoing PLN transfer pays. " <>
                    "Considers months with logged time up to six months back whose salary is not yet assigned and " <>
                    "whose closest estimated payout is within 20% (at least 1000 PLN) of the transfer. When the employee's " <>
                    "stored bank account is known, it decides instead: a transfer to that account is suggested " <>
                    "whatever the amount and ranked first, a transfer to another account is not. Uses gross pay " <>
                    "only if the contract type is unknown. A full recipient name strictly outranks a partial name, " <>
                    "the expected month and the amount difference. A payout variant is a hypothesis, not confirmed " <>
                    "insurance or tax status. By default only salaries with a submitted hours " <>
                    "record count. An empty result has a reason. Requires an administrator. Changes nothing."
    end

    tool :connect_transaction_salary, Transaction, :connect_salary do
      annotations title: "Assign transfer to salary",
                  read_only_hint: false,
                  destructive_hint: false,
                  idempotent_hint: true,
                  open_world_hint: false

      description "Settle one employee's monthly salary with a pending outgoing transfer, only after the user " <>
                    "approves the specific match. Pass the transaction id, salary_user_id and salary_month (first " <>
                    "day of the month). Repeating an existing assignment succeeds without changes. Restore a skipped " <>
                    "transfer first. A salary month can be paid by one transfer only; conflicts with another " <>
                    "transfer, salary or invoice return an error naming them and change nothing. Requires an " <>
                    "administrator."

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

    resource Firmowid.Finances.Institution do
      define :list_institutions, action: :for_country, args: [:country]
    end

    resource Firmowid.Finances.Requisition do
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

      define :update_transaction_internal_note,
        action: :update_internal_note,
        args: [:internal_note]

      define :restore_transaction_for_matching, action: :restore_for_matching
      define :list_monthly_salaries, action: :monthly_salaries, args: [:month]
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
