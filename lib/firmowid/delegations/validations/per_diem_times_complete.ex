defmodule Firmowid.Delegations.Validations.PerDiemTimesComplete do
  @moduledoc "Requires the trip times the per diem is calculated from, in chronological order."

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    fields =
      if Ash.Changeset.get_attribute(changeset, :destination_country) == "PL",
        do: [:trip_started_at, :trip_ended_at],
        else: [:trip_started_at, :abroad_started_at, :abroad_ended_at, :trip_ended_at]

    times = Enum.map(fields, &{&1, Ash.Changeset.get_attribute(changeset, &1)})

    case Enum.find(times, fn {_field, time} -> is_nil(time) end) do
      {field, nil} -> {:error, field: field, message: gettext_noop("Fill in this field.")}
      nil -> validate_order(times)
    end
  end

  defp validate_order(times) do
    times
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{_earlier, earlier}, {_later, later}] ->
      NaiveDateTime.after?(earlier, later)
    end)
    |> case do
      [_earlier, {field, _time}] ->
        {:error, field: field, message: gettext_noop("The times must be in chronological order.")}

      nil ->
        :ok
    end
  end
end
