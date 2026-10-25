defmodule FirmowidWeb.Infrastructure.Utilities.LocalTime do
  @moduledoc """
  Converts wall-clock dates and times entered in a user's time zone to UTC, including
  the hour that daylight saving time repeats or skips.
  """

  @doc """
  Returns the UTC instant for `date` and `time` on the wall clock of `timezone`.

  An hour repeated by the autumn clock change resolves to its first occurrence; an
  hour skipped by the spring clock change resolves to the first instant after the gap.
  """
  @spec to_utc(Date.t(), Time.t(), String.t()) :: DateTime.t()
  def to_utc(date, time, timezone) do
    local =
      case DateTime.new(date, time, timezone) do
        {:ok, datetime} -> datetime
        {:ambiguous, first_occurrence, _second_occurrence} -> first_occurrence
        {:gap, _just_before, just_after} -> just_after
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end
end
