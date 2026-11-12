defmodule Firmowid.Delegations.Changes.UpdateDetectedDelegationDates do
  @moduledoc "Updates a delegation's detected date range after evidence changes."

  use Ash.Resource.Change

  alias Firmowid.Delegations
  alias Firmowid.Delegations.Delegation
  alias Firmowid.Delegations.DelegationExpense
  alias Firmowid.Delegations.DelegationExpense.Trip

  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, expense ->
      with {:ok, delegation} <-
             Delegations.get_delegation(expense.delegation_id,
               scope: context,
               load: [:expenses]
             ),
           expenses = expenses_after_action(delegation.expenses, expense, opts),
           {:ok, _delegation} <-
             Delegations.detect_dates(delegation, detected_dates(delegation, expenses), scope: context) do
        {:ok, expense}
      end
    end)
  end

  @doc """
  Returns the earliest and latest evidence dates of `expenses` when they fall before the
  delegation's start date or after its end date, and `nil` for a side they stay within.
  """
  @spec detected_dates(Delegation.t(), [DelegationExpense.t()]) ::
          %{detected_start_date: Date.t() | nil, detected_end_date: Date.t() | nil}
  def detected_dates(delegation, expenses) do
    dates = Enum.flat_map(expenses, &expense_dates/1)
    earliest = Enum.min(dates, Date, fn -> nil end)
    latest = Enum.max(dates, Date, fn -> nil end)

    %{
      detected_start_date: if(earliest && Date.before?(earliest, delegation.start_date), do: earliest),
      detected_end_date: if(latest && Date.after?(latest, delegation.end_date), do: latest)
    }
  end

  defp expenses_after_action(expenses, expense, operation: :destroy) do
    Enum.reject(expenses, &(&1.id == expense.id))
  end

  defp expenses_after_action(expenses, expense, _opts) do
    [expense | Enum.reject(expenses, &(&1.id == expense.id))]
  end

  defp expense_dates(%{details: %Ash.Union{value: %{trips: trips}}}), do: Enum.flat_map(trips, &Trip.evidence_dates/1)

  defp expense_dates(%{details: %Ash.Union{value: %{arrival_date: arrival_date, departure_date: departure_date}}}),
    do: Enum.reject([arrival_date, departure_date], &is_nil/1)

  defp expense_dates(_expense), do: []
end
