defmodule Firmowid.Ash.Timetracker.Changes.ClampSessionBoundaries do
  @moduledoc """
  Clamps a clock-derived session end so it never violates the boundary rules
  enforced by `Firmowid.Ash.Timetracker.Validations.SessionMonthBoundaries`.

  Used by `:stop` and `:auto_stop`, which derive `end_datetime` from the clock
  and must never be rejected — a user must always be able to stop a timer. The
  effective ceiling is whichever limit binds first: the end of the calendar
  month the session started in, or the maximum session duration.

  Only ever shortens the session, so it cannot introduce an overlap. A running
  session already extends to `infinity` in the database overlap trigger, so no
  other session can exist in the window being trimmed away.
  """

  use Ash.Resource.Change

  alias Firmowid.Ash.Timetracker.Validations.SessionMonthBoundaries

  @impl true
  def change(changeset, _opts, _context) do
    start_datetime = Ash.Changeset.get_attribute(changeset, :start_datetime)
    end_datetime = Ash.Changeset.get_attribute(changeset, :end_datetime)

    case {start_datetime, end_datetime} do
      {%DateTime{} = start_datetime, %DateTime{} = end_datetime} ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :end_datetime,
          clamp(start_datetime, end_datetime)
        )

      _incomplete ->
        changeset
    end
  end

  # Clamps end_datetime down to the first limit that binds: the end of the month
  # the session started in, or the maximum session duration.
  defp clamp(%DateTime{} = start_datetime, %DateTime{} = end_datetime) do
    ceiling =
      min_datetime(
        end_of_start_month(start_datetime),
        DateTime.shift(start_datetime, second: SessionMonthBoundaries.max_session_seconds())
      )

    if DateTime.after?(end_datetime, ceiling), do: ceiling, else: end_datetime
  end

  # Last minute of the calendar month the session started in.
  defp end_of_start_month(%DateTime{} = start_datetime) do
    start_datetime
    |> DateTime.to_date()
    |> Date.end_of_month()
    |> DateTime.new!(~T[23:59:00], "Etc/UTC")
  end

  defp min_datetime(%DateTime{} = a, %DateTime{} = b) do
    if DateTime.after?(a, b), do: b, else: a
  end
end
