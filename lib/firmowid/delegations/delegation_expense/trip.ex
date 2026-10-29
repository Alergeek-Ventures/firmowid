defmodule Firmowid.Delegations.DelegationExpense.Trip do
  @moduledoc "One route segment recorded on a transport expense document."

  use Ash.Resource, data_layer: :embedded, embed_nil_values?: false
  use Gettext, backend: Firmowid.Gettext

  validations do
    validate compare(:arrival_datetime, greater_than_or_equal_to: :departure_datetime),
      where: [present(:arrival_datetime), present(:departure_datetime)],
      message: gettext_noop("must be at the same time as the departure or later")
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :departure_city, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    attribute :departure_local_datetime, :naive_datetime, public?: true
    attribute :departure_datetime, :utc_datetime, public?: true

    attribute :arrival_city, :string,
      allow_nil?: false,
      default: "",
      constraints: [allow_empty?: true],
      public?: true

    attribute :arrival_local_datetime, :naive_datetime, public?: true
    attribute :arrival_datetime, :utc_datetime, public?: true
    attribute :description, :string, public?: true
  end

  @doc "Returns the ticket wall clock, falling back to legacy UTC components without conversion."
  @spec local_datetime(t(), :departure | :arrival) :: NaiveDateTime.t() | nil
  def local_datetime(trip, :departure) do
    trip.departure_local_datetime || legacy_datetime(trip.departure_datetime)
  end

  def local_datetime(trip, :arrival) do
    trip.arrival_local_datetime || legacy_datetime(trip.arrival_datetime)
  end

  @doc "Returns evidence dates from ticket wall clocks, with legacy UTC fallback."
  @spec evidence_dates(t()) :: [Date.t()]
  def evidence_dates(trip) do
    [:departure, :arrival]
    |> Enum.map(&local_datetime(trip, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&NaiveDateTime.to_date/1)
  end

  defp legacy_datetime(nil), do: nil
  defp legacy_datetime(%DateTime{} = datetime), do: DateTime.to_naive(datetime)
end
