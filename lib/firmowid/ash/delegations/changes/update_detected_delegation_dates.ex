defmodule Firmowid.Ash.Delegations.Changes.UpdateDetectedDelegationDates do
  @moduledoc "Updates a delegation's detected date range after evidence is added."

  use Ash.Resource.Change

  alias Firmowid.Ash.Delegations

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, expense ->
      with {:ok, delegation} <-
             Delegations.get_delegation(expense.delegation_id,
               load: [:expenses],
               actor: context.actor,
               tenant: context.tenant
             ),
           {:ok, _delegation} <- update_dates(delegation, expense, context) do
        {:ok, expense}
      end
    end)
  end

  defp update_dates(delegation, expense, context) do
    dates = delegation.expenses |> prepend_expense(expense) |> Enum.flat_map(&expense_dates/1)

    delegation
    |> Ash.Changeset.for_update(:detect_dates, detected_date_params(delegation, dates),
      actor: context.actor,
      tenant: context.tenant
    )
    |> Ash.update()
  end

  defp prepend_expense(expenses, expense) do
    [expense | Enum.reject(expenses, &(&1.id == expense.id))]
  end

  defp expense_dates(%{details: %Ash.Union{value: details}}), do: expense_dates(details)

  defp expense_dates(%{trips: trips}) when is_list(trips) do
    trips
    |> Enum.flat_map(fn trip ->
      [date_from_datetime(trip.departure_datetime), date_from_datetime(trip.arrival_datetime)]
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp expense_dates(%{arrival_date: arrival_date, departure_date: departure_date}) do
    Enum.reject([arrival_date, departure_date], &is_nil/1)
  end

  defp expense_dates(_expense), do: []

  defp date_from_datetime(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp date_from_datetime(_datetime), do: nil

  defp detected_date_params(_delegation, []), do: %{detected_start_date: nil, detected_end_date: nil}

  defp detected_date_params(delegation, dates) do
    earliest_date = Enum.min_by(dates, &Date.to_iso8601/1)
    latest_date = Enum.max_by(dates, &Date.to_iso8601/1)

    %{
      detected_start_date: detected_start_date(earliest_date, delegation.start_date),
      detected_end_date: detected_end_date(latest_date, delegation.end_date)
    }
  end

  defp detected_start_date(date, start_date) do
    if before_delegation?(date, start_date), do: date
  end

  defp detected_end_date(date, end_date) do
    if after_delegation?(date, end_date), do: date
  end

  defp before_delegation?(date, start_date), do: Date.before?(date, start_date)
  defp after_delegation?(date, end_date), do: Date.after?(date, end_date)
end
