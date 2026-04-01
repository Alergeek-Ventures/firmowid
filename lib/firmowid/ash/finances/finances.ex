defmodule Firmowid.Ash.Finances do
  @moduledoc """
  Ash domain for bank accounts and transactions.

  Manages bank account CRUD, transaction synchronization from bank APIs,
  transaction search (ParadeDB), and invoicing-related transaction queries.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Finances.BankAccount do
      define :get_bank_account, action: :read, get_by: [:id]
      define :list_bank_accounts, action: :read
      define :sync_bank_account, action: :sync_from_bank
      define :create_manual_bank_account, action: :create_manual
      define :update_bank_account, action: :update
      define :destroy_bank_account, action: :destroy
      define :list_bank_accounts_for_sync, action: :list_for_sync
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
end
