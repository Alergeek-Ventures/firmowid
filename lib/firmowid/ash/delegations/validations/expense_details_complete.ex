defmodule Firmowid.Ash.Delegations.Validations.ExpenseDetailsComplete do
  @moduledoc "Validates category-specific fields when a delegation is completed."

  use Ash.Resource.Validation

  alias Firmowid.Ash.Delegations.DelegationExpense.AccommodationDetails
  alias Firmowid.Ash.Delegations.DelegationExpense.OtherDetails
  alias Firmowid.Ash.Delegations.DelegationExpense.TransportDetails

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :details) do
      %TransportDetails{trips: trips} when is_list(trips) and trips != [] ->
        validate_trips(trips)

      %TransportDetails{} ->
        {:error, field: :details, message: "Dodaj przynajmniej jedną trasę."}

      %AccommodationDetails{} = details ->
        validate_accommodation(details)

      %OtherDetails{description: description} when is_binary(description) and description != "" ->
        :ok

      %OtherDetails{} ->
        {:error, field: :details, message: "Uzupełnij opis."}

      _ ->
        {:error, field: :details, message: "Uzupełnij szczegóły wydatku."}
    end
  end

  defp validate_trips(trips) do
    if Enum.all?(trips, &valid_trip?/1),
      do: :ok,
      else: {:error, field: :details, message: "Uzupełnij poprawnie każdą trasę."}
  end

  defp valid_trip?(%{
         departure_city: departure_city,
         arrival_city: arrival_city,
         departure_datetime: departure_datetime,
         arrival_datetime: arrival_datetime
       }) do
    departure_city != "" and arrival_city != "" and not is_nil(departure_datetime) and
      not is_nil(arrival_datetime) and
      DateTime.compare(arrival_datetime, departure_datetime) in [:gt, :eq]
  end

  defp valid_trip?(_), do: false

  defp validate_accommodation(%{locality: locality, arrival_date: arrival_date, departure_date: departure_date}) do
    if locality != "" and not is_nil(arrival_date) and not is_nil(departure_date) and
         Date.compare(departure_date, arrival_date) in [:gt, :eq],
       do: :ok,
       else: {:error, field: :details, message: "Uzupełnij poprawnie dane noclegu."}
  end
end
