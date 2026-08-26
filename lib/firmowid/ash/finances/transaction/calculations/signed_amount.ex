defmodule Firmowid.Ash.Finances.Transaction.Calculations.SignedAmount do
  @moduledoc "Returns the transaction amount with the canonical direction's sign."

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:amount, :direction]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn transaction ->
      amount = Money.abs(transaction.amount)

      if transaction.direction == :income, do: amount, else: Money.negate!(amount)
    end)
  end
end
