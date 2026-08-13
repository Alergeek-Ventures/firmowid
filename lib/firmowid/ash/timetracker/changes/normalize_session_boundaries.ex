defmodule Firmowid.Ash.Timetracker.Changes.NormalizeSessionBoundaries do
  @moduledoc """
  Stores time tracking session boundaries at minute precision.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Enum.reduce([:start_datetime, :end_datetime], changeset, fn field, changeset ->
      case Ash.Changeset.get_attribute(changeset, field) do
        nil ->
          changeset

        datetime ->
          Ash.Changeset.force_change_attribute(changeset, field, truncate_to_minute(datetime))
      end
    end)
  end

  defp truncate_to_minute(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.shift(second: -datetime.second)
  end
end
