defmodule Firmowid.Ash.Timetracker.TrimPlan do
  @moduledoc """
  Computes the set of changes needed to make room for a new session
  by trimming, deleting, or splitting overlapping sessions.

  All functions are pure — they take session structs and return a list
  of planned actions without touching the database.

  ## Action types

    * `{:trim_end, session, new_end}` — shorten session's end to `new_end`
    * `{:trim_start, session, new_start}` — shorten session's start to `new_start`
    * `{:delete, session}` — remove session entirely (fully contained in new range)
    * `{:split, session, new_end, remainder_attrs}` — trim original's end to `new_end`
      and create a remainder session with `remainder_attrs`
  """

  @type session :: map()

  @type action ::
          {:trim_end, session(), DateTime.t()}
          | {:trim_start, session(), DateTime.t()}
          | {:delete, session()}
          | {:split, session(), DateTime.t(), map()}

  @doc """
  Computes the trim plan for inserting a new session into a time range
  that overlaps with existing sessions.

  Returns `{:ok, actions}` with a list of actions to execute, or
  `{:error, :locked_conflict, locked_sessions}` if any overlapping
  session is locked (hours record submitted).

  ## Parameters

    * `new_start` — start datetime of the new session
    * `new_end` — end datetime of the new session (nil = running/open)
    * `overlapping_sessions` — list of sessions that overlap with the new range,
      as returned by the `:list_overlapping` read action. Must have `:lockdown` loaded.
  """
  @spec compute(DateTime.t(), DateTime.t() | nil, [session()]) ::
          {:ok, [action()]} | {:error, :locked_conflict, [session()]}
  def compute(new_start, new_end, overlapping_sessions) do
    locked = Enum.filter(overlapping_sessions, & &1.lockdown)

    if locked == [] do
      actions = Enum.flat_map(overlapping_sessions, &plan_action(&1, new_start, new_end))
      {:ok, actions}
    else
      {:error, :locked_conflict, locked}
    end
  end

  # Computes the action(s) for a single overlapping session.
  #
  # The four cases, determined by comparing the existing session's range
  # against the new session's range:
  #
  #   existing:  |-------|           (s_start to s_end)
  #   new:           |-------|       (new_start to new_end)
  #
  # Case 1 - End trim:    s_start < new_start, s_end inside new range
  # Case 2 - Start trim:  s_start inside new range, s_end > new_end
  # Case 3 - Delete:      s fully contained within new range
  # Case 4 - Split:       s fully contains new range
  defp plan_action(session, new_start, new_end) do
    s_start = session.start_datetime
    s_end = session.end_datetime

    cond do
      fully_contains?(s_start, s_end, new_start, new_end) ->
        # Existing session wraps around new session — split it
        remainder_attrs = %{
          title: session.title,
          start_datetime: new_end,
          end_datetime: s_end,
          project_id: session.project_id,
          is_remote: session.is_remote,
          user_id: session.user_id
        }

        [{:split, session, new_start, remainder_attrs}]

      fully_contained?(s_start, s_end, new_start, new_end) ->
        # Existing session is entirely within new range — delete it
        [{:delete, session}]

      overlaps_end?(s_start, s_end, new_start) ->
        # Existing session starts before new, ends during new — trim end
        [{:trim_end, session, new_start}]

      overlaps_start?(s_start, s_end, new_start, new_end) ->
        # Existing session starts during new, ends after new — trim start
        [{:trim_start, session, new_end}]
    end
  end

  # Existing session fully contains the new range:
  # s_start < new_start AND s_end > new_end (or s_end is nil and new_end is not nil)
  defp fully_contains?(s_start, s_end, new_start, new_end) do
    DateTime.before?(s_start, new_start) and after_end?(s_end, new_end)
  end

  # Existing session is fully contained within the new range:
  # s_start >= new_start AND s_end <= new_end
  # If new_end is nil (running), any session starting after new_start is contained
  # (unless it's also running — a running session extends to infinity, so it can't
  # be contained by another running session)
  defp fully_contained?(s_start, s_end, new_start, new_end) do
    not DateTime.before?(s_start, new_start) and not after_end?(s_end, new_end)
  end

  # Existing session overlaps at the end: starts before new_start, ends during new range
  defp overlaps_end?(s_start, _s_end, new_start) do
    DateTime.before?(s_start, new_start)
  end

  # Existing session overlaps at the start: starts during new range, ends after new_end
  defp overlaps_start?(_s_start, s_end, _new_start, new_end) do
    after_end?(s_end, new_end)
  end

  # Is `s_end` strictly after `new_end`?
  # nil end means infinity, which is after everything except another nil
  defp after_end?(nil, nil), do: false
  defp after_end?(nil, _new_end), do: true
  defp after_end?(_s_end, nil), do: false
  defp after_end?(s_end, new_end), do: DateTime.after?(s_end, new_end)
end
