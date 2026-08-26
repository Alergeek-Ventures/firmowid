defmodule Firmowid.Ash.Finances.Transaction.Calculations.Direction do
  @moduledoc """
  Calculates the canonical, account-aware direction of a transaction.

  The connected bank account takes precedence over the imported amount sign.
  """

  use Ash.Resource.Calculation

  alias Firmowid.Ash.Finances.TransactionDirection

  @impl true
  def load(_query, _opts, _context) do
    [:amount, :debtor_account, :creditor_account, bank_account: :iban]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &TransactionDirection.direction/1)
  end
end
