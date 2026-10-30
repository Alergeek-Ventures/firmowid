defmodule Firmowid.Delegations.Validations.ExpenseDetailsComplete do
  @moduledoc "Validates category-specific fields when a delegation is completed."

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Delegations.DelegationExpense.AccommodationDetails
  alias Firmowid.Delegations.DelegationExpense.OtherDetails
  alias Firmowid.Delegations.DelegationExpense.TransportDetails
  alias Firmowid.Delegations.DelegationExpense.Trip

  @impl true
  def validate(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.get_attribute(:details)
    |> validate_details()
  end

  defp validate_details(%Ash.Union{value: details}), do: validate_details(details)

  defp validate_details(details) do
    case details do
      %TransportDetails{trips: trips} when is_list(trips) and trips != [] ->
        validate_trips(trips)

      %TransportDetails{} ->
        {:error, field: :details, message: gettext_noop("Add at least one route.")}

      %AccommodationDetails{} = details ->
        validate_accommodation(details)

      %OtherDetails{description: description} when is_binary(description) and description != "" ->
        :ok

      %OtherDetails{} ->
        {:error, field: :details, message: gettext_noop("Fill in the description.")}

      _ ->
        {:error, field: :details, message: gettext_noop("Fill in the expense details.")}
    end
  end

  defp validate_trips(trips) do
    if Enum.all?(trips, &valid_trip?/1),
      do: :ok,
      else: {:error, field: :details, message: gettext_noop("Fill in every route correctly.")}
  end

  defp valid_trip?(%Trip{} = trip) do
    trip.departure_city != "" and trip.arrival_city != "" and
      not is_nil(Trip.local_datetime(trip, :departure)) and
      not is_nil(Trip.local_datetime(trip, :arrival)) and chronological?(trip)
  end

  defp valid_trip?(_), do: false

  defp chronological?(%{departure_datetime: %DateTime{} = departure, arrival_datetime: %DateTime{} = arrival}) do
    DateTime.compare(arrival, departure) in [:gt, :eq]
  end

  defp chronological?(_trip), do: true

  defp validate_accommodation(%{locality: locality, arrival_date: arrival_date, departure_date: departure_date}) do
    if locality != "" and not is_nil(arrival_date) and not is_nil(departure_date) and
         Date.compare(departure_date, arrival_date) in [:gt, :eq],
       do: :ok,
       else: {:error, field: :details, message: gettext_noop("Fill in the accommodation details correctly.")}
  end
end
