defmodule Firmowid.Ash.Delegations.Changes.ValidateSettlement do
  @moduledoc "Prevents completing delegations with incomplete settlement details."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    case Ash.load(changeset.data, expense_loads(), actor: context.actor, tenant: context.tenant) do
      {:ok, delegation} ->
        if complete?(delegation),
          do: changeset,
          else: Ash.Changeset.add_error(changeset, incomplete_error())

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp expense_loads do
    [:accommodation_expenses, :other_expenses, transport_expenses: [:trips]]
  end

  defp complete?(delegation) do
    expenses =
      delegation.transport_expenses ++
        delegation.accommodation_expenses ++ delegation.other_expenses

    expenses != [] and
      Enum.all?(expenses, &valid_document?/1) and
      Enum.all?(delegation.transport_expenses, &valid_transport?/1) and
      Enum.all?(delegation.accommodation_expenses, &valid_accommodation?/1)
  end

  defp valid_document?(expense) do
    String.trim(expense.document_number) != "" and
      Money.compare(expense.expense_amount, Money.new(:PLN, 0)) == :gt
  end

  defp valid_transport?(%{trips: trips}) when is_list(trips) and trips != [], do: Enum.all?(trips, &valid_trip?/1)

  defp valid_transport?(_expense), do: false

  defp valid_trip?(trip) do
    String.trim(trip.departure_city) != "" and
      String.trim(trip.arrival_city) != "" and
      match?(%DateTime{}, trip.departure_datetime) and
      match?(%DateTime{}, trip.arrival_datetime) and
      DateTime.compare(trip.arrival_datetime, trip.departure_datetime) in [:eq, :gt]
  end

  defp valid_accommodation?(expense) do
    String.trim(expense.locality) != "" and
      match?(%Date{}, expense.arrival_date) and
      match?(%Date{}, expense.departure_date) and
      Date.compare(expense.departure_date, expense.arrival_date) in [:eq, :gt]
  end

  defp incomplete_error do
    "Uzupełnij poprawnie wszystkie dokumenty, trasy i daty przed wysłaniem rozliczenia."
  end
end
