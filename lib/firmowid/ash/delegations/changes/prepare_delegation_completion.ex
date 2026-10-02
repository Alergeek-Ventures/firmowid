defmodule Firmowid.Ash.Delegations.Changes.PrepareDelegationCompletion do
  @moduledoc "Validates final expense data and derives evidence dates before completion."

  use Ash.Resource.Change

  alias Firmowid.Ash.Delegations.DelegationExpense

  @impl true
  def change(changeset, _opts, context) do
    case Ash.load(changeset.data, [:expenses], actor: context.actor, tenant: context.tenant) do
      {:ok, delegation} -> prepare(changeset, delegation.expenses, context)
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp prepare(changeset, expenses, context) do
    expense_params = expense_params_by_id(Ash.Changeset.get_argument(changeset, :expenses))

    final_expenses =
      Enum.map(expenses, fn expense ->
        params =
          expense_params
          |> Map.get(to_string(expense.id), %{})
          |> Map.drop([:id, "id"])

        Ash.Changeset.for_update(expense, :complete, params,
          actor: context.actor,
          tenant: context.tenant
        )
      end)

    case Enum.find(final_expenses, &(not &1.valid?)) do
      nil ->
        dates =
          final_expenses
          |> Enum.map(&Ash.Changeset.apply_attributes/1)
          |> Enum.flat_map(&expense_dates/1)

        detected_start_date = detected_start_date(dates, changeset.data.start_date)
        detected_end_date = detected_end_date(dates, changeset.data.end_date)

        changeset
        |> Ash.Changeset.change_attribute(:detected_start_date, detected_start_date)
        |> Ash.Changeset.change_attribute(:detected_end_date, detected_end_date)
        |> require_date_change_reason(detected_start_date, detected_end_date)

      invalid_changeset ->
        Ash.Changeset.add_error(changeset, invalid_changeset.errors)
    end
  end

  defp expense_params_by_id(expenses) do
    Map.new(expenses, fn params -> {to_string(params[:id] || params["id"]), params} end)
  end

  defp expense_dates(%DelegationExpense{details: %Ash.Union{value: details}}), do: expense_dates(details)

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

  defp detected_start_date([], _start_date), do: nil

  defp detected_start_date(dates, start_date) do
    date = Enum.min_by(dates, &Date.to_iso8601/1)
    if Date.before?(date, start_date), do: date
  end

  defp detected_end_date([], _end_date), do: nil

  defp detected_end_date(dates, end_date) do
    date = Enum.max_by(dates, &Date.to_iso8601/1)
    if Date.after?(date, end_date), do: date
  end

  defp require_date_change_reason(changeset, nil, nil), do: changeset

  defp require_date_change_reason(changeset, _detected_start_date, _detected_end_date) do
    if blank?(Ash.Changeset.get_attribute(changeset, :date_change_reason)) do
      Ash.Changeset.add_error(changeset,
        field: :date_change_reason,
        message: "To pole jest wymagane"
      )
    else
      changeset
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
