defmodule Firmowid.Ash.Finances do
  @moduledoc """
  Ash domain for bank accounts and transactions.

  Manages bank account CRUD, transaction synchronization from bank APIs,
  transaction search (ParadeDB), and invoicing-related transaction queries.
  """
  use Ash.Domain

  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Scope

  require Ash.Query

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
      define :list_requisitions, action: :read
    end

    resource Firmowid.Ash.Finances.Transaction do
      define :get_transaction, action: :read, get_by: [:id]
      define :list_transactions, action: :read
      define :upsert_transaction_from_sync, action: :upsert_from_sync
      define :set_transaction_skip_invoicing, action: :set_skip_invoicing
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
    BankAccount
    |> Ash.Query.for_read(:read, %{}, scope: scope)
    |> Ash.Query.filter(is_default == true and currency == ^currency)
    |> Ash.Query.select([:id, :iban, :currency, :is_default])
    |> Ash.read_one(scope: scope)
  end
end
