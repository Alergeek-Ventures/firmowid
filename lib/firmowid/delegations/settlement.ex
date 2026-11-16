defmodule Firmowid.Delegations.Settlement do
  @moduledoc "Totals of a prepared delegation settlement: what the trip cost and who owes whom."

  alias Firmowid.Delegations.PerDiem

  @doc """
  Adds the per diem and lump sums to the settled expenses. Expects the expenses loaded and a
  prepared settlement, whose expenses all have a PLN settlement amount.
  """
  @spec total(map()) :: Money.t()
  def total(delegation) do
    per_diem = PerDiem.for_delegation(delegation)
    initial = if per_diem, do: per_diem.total, else: Money.new(:PLN, 0)

    Enum.reduce(delegation.expenses, initial, fn expense, total ->
      Money.add!(total, expense.settlement_amount || expense.expense_amount)
    end)
  end
end
