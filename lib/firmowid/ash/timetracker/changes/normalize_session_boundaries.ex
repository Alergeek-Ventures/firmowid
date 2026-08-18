defmodule Firmowid.Ash.Timetracker.Changes.NormalizeSessionBoundaries do
  @moduledoc """
  Stores time tracking session boundaries at minute precision.
  """
  use Ash.Resource.Change

  @doc """
  Truncates a session boundary to minute precision.
  """
  @spec datetime(DateTime.t() | nil) :: DateTime.t() | nil
  def datetime(nil), do: nil

  def datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.shift(second: -datetime.second)
  end

  @impl true
  def change(changeset, _opts, _context) do
    Enum.reduce([:start_datetime, :end_datetime], changeset, fn field, changeset ->
      case Ash.Changeset.get_attribute(changeset, field) do
        nil ->
          changeset

        datetime ->
          Ash.Changeset.force_change_attribute(changeset, field, datetime(datetime))
      end
    end)
  end
end
