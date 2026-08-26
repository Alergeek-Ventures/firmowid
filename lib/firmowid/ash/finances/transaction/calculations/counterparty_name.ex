defmodule Firmowid.Ash.Finances.Transaction.Calculations.CounterpartyName do
  @moduledoc "Selects the raw counterparty field appropriate for the direction."

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:direction, :debtor_name, :creditor_name]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn transaction ->
      if transaction.direction == :income,
        do: transaction.debtor_name,
        else: transaction.creditor_name
    end)
  end
end
