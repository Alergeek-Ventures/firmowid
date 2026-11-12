defmodule Firmowid.Timetracker.Changes.ClampSessionBoundaries do
  @moduledoc """
  Clamps a clock-derived session end so it never violates the boundary rules
  enforced by `Firmowid.Timetracker.Validations.SessionMonthBoundaries`.

  Used by `:stop` and `:auto_stop`, which derive `end_datetime` from the clock
  and must never be rejected — a user must always be able to stop a timer. The
  effective ceiling is whichever limit binds first: the end of the calendar
  month the session started in, or the maximum running time, after which the
  `:auto_stop` trigger ends a forgotten session.

  The end is stored at minute precision, or at the start when that lies later,
  and the start stays as stored. So the change only ever shortens the session
  and cannot introduce an overlap: a running session already extends to
  `infinity` in the database overlap trigger, so no other session can exist in
  the window being trimmed away. Moving the start to its minute would break
  that for a session stored with seconds whose predecessor ended in the same
  minute.
  """

  use Ash.Resource.Change

  alias Firmowid.Timetracker.Changes.NormalizeSessionBoundaries

  @max_running_seconds 12 * 3600

  @doc "The longest a session can run before it is stopped, in seconds."
  @spec max_running_seconds() :: pos_integer()
  def max_running_seconds, do: @max_running_seconds

  # Both actions run on a stored session and set its end from the clock first.
  @impl true
  def change(changeset, _opts, _context) do
    start_datetime = Ash.Changeset.get_attribute(changeset, :start_datetime)
    end_datetime = Ash.Changeset.get_attribute(changeset, :end_datetime)

    end_datetime = start_datetime |> clamp(end_datetime) |> NormalizeSessionBoundaries.datetime()

    # A start stored with seconds can lie after the minute its end falls in, for
    # example in the last minute of its month; the session then ends where it began.
    end_datetime =
      if DateTime.before?(end_datetime, start_datetime), do: start_datetime, else: end_datetime

    Ash.Changeset.force_change_attribute(changeset, :end_datetime, end_datetime)
  end

  # Clamps end_datetime down to the first limit that binds: the end of the month
  # the session started in, or the maximum running time.
  defp clamp(%DateTime{} = start_datetime, %DateTime{} = end_datetime) do
    ceiling =
      min_datetime(
        end_of_start_month(start_datetime),
        DateTime.shift(start_datetime, second: @max_running_seconds)
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
