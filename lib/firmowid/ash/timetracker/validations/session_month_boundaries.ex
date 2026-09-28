defmodule Firmowid.Ash.Timetracker.Validations.SessionMonthBoundaries do
  @moduledoc """
  Keeps an authored session inside one calendar month and under a maximum
  duration.

  ## Actions that derive the end from the clock

  `:stop` and `:auto_stop` set `end_datetime` from the current time and must
  never be rejected — a user must always be able to stop a timer. They are
  matched **by action name** and skipped here, because `on:` matches action
  *types*, which would otherwise sweep them in alongside the authored ones. They
  clamp instead, via
  `Firmowid.Ash.Timetracker.Changes.ClampSessionBoundaries`.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @max_session_seconds 24 * 3600

  @doc """
  The longest session a user may author by hand, in seconds.

  Read by `Firmowid.Ash.Timetracker.Changes.ClampSessionBoundaries`, which must
  clamp to the same ceiling this validation enforces.
  """
  @spec max_session_seconds() :: pos_integer()
  def max_session_seconds, do: @max_session_seconds

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    start_datetime = Ash.Changeset.get_attribute(changeset, :start_datetime)
    end_datetime = Ash.Changeset.get_attribute(changeset, :end_datetime)

    cond do
      clock_derived_action?(changeset) ->
        :ok

      not boundary_written?(changeset) ->
        :ok

      is_nil(start_datetime) or is_nil(end_datetime) ->
        :ok

      crosses_month_boundary?(start_datetime, end_datetime) ->
        error(
          :end_datetime,
          "Data zakończenia musi przypadać w tym samym miesiącu co data rozpoczęcia"
        )

      too_long?(start_datetime, end_datetime) ->
        error(:end_datetime, "Sesja nie może trwać dłużej niż 24 godziny")

      true ->
        :ok
    end
  end

  defp crosses_month_boundary?(%DateTime{} = start_datetime, %DateTime{} = end_datetime) do
    {start_datetime.year, start_datetime.month} != {end_datetime.year, end_datetime.month}
  end

  defp too_long?(%DateTime{} = start_datetime, %DateTime{} = end_datetime) do
    DateTime.diff(end_datetime, start_datetime) > max_session_seconds()
  end

  # Actions that derive end_datetime from the clock instead of accepting it from
  # the caller.
  defp clock_derived_action?(changeset), do: changeset.action.name in [:stop, :auto_stop]

  # Whether the changeset actually writes a session boundary, as opposed to
  # leaving both untouched. Keeps unrelated edits (title, project) working on
  # rows that predate these rules, which the timetracker UI resubmits in full.
  defp boundary_written?(%Ash.Changeset{action_type: :create}), do: true

  defp boundary_written?(%Ash.Changeset{data: data} = changeset) do
    Ash.Changeset.get_attribute(changeset, :start_datetime) != data.start_datetime or
      Ash.Changeset.get_attribute(changeset, :end_datetime) != data.end_datetime
  end

  defp error(field, message) do
    {:error, InvalidAttribute.exception(field: field, message: message)}
  end
end
