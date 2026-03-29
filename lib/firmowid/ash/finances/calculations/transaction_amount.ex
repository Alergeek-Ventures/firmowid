defmodule Firmowid.Ash.Finances.Calculations.TransactionAmount do
  @moduledoc """
  Combines `transaction_currency` and `transaction_amount` into a `Money` struct.

  Replaces the manual `Money.new(t.transaction_currency, t.transaction_amount)`
  pattern scattered across LiveView and component modules. Callers explicitly
  load this calculation when they need the Money representation:

      transaction |> Ash.load!(:amount)
      Ash.Query.load(query, :amount)

  Returns `nil` when either currency or amount is missing.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:transaction_currency, :transaction_amount]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      if record.transaction_currency && record.transaction_amount do
        Money.new(record.transaction_currency, record.transaction_amount)
      end
    end)
  end
end
