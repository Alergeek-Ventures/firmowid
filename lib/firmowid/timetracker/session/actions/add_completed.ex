defmodule Firmowid.Timetracker.Session.Actions.AddCompleted do
  @moduledoc """
  Adds completed sessions with explicit boundaries for the acting member.

  Runs inside the action's transaction: the first rejected session rolls back
  every session added before it. Errors carry the session's position in the
  `sessions` argument. A running session is never touched; it only counts as
  an overlap from its start onwards, as in the database trigger.
  """

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Timetracker.Checks.HoursRecordNotSubmitted
  alias Firmowid.Timetracker.Session

  @doc "Creates every session for the action actor or none of them."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, [Session.t()]} | {:error, term()}
  def run(input, context) do
    opts = Ash.Context.to_opts(context)
    member_id = context.actor.member.id

    input.arguments.sessions
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {attrs, index}, {:ok, sessions} ->
      case add(attrs, member_id, context.actor, opts) do
        {:ok, session} -> {:cont, {:ok, [session | sessions]}}
        {:error, error} -> {:halt, {:error, Ash.Error.set_path(error, [:sessions, index])}}
      end
    end)
    |> case do
      {:ok, sessions} -> {:ok, Enum.reverse(sessions)}
      error -> error
    end
  end

  defp add(attrs, member_id, actor, opts) do
    changeset =
      attrs
      |> Map.put(:member_id, member_id)
      |> Session.changeset_to_create(opts)
      |> Ash.Changeset.before_action(&refute_overlap(&1, opts))

    with :ok <- refute_submitted_month(changeset, actor) do
      # The action's own transaction rolls back every session; returning the
      # error here keeps the item position added in run/2.
      Ash.create(changeset, Keyword.put(opts, :rollback_on_error?, false))
    end
  end

  # Like edit_session, this self-service action respects a submitted month for
  # administrators too, who bypass the :create policy. Checked up front so the
  # error names the field; SynchronizeSubmittedMonth still guards employees
  # against a submission racing this insert.
  defp refute_submitted_month(changeset, actor) do
    case HoursRecordNotSubmitted.match?(actor, %{subject: changeset}, []) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        {:error,
         InvalidAttribute.exception(
           field: :start_datetime,
           message: "falls in a month with a submitted hours record"
         )}
    end
  end

  # Runs after validation and the member lock taken by SynchronizeSubmittedMonth,
  # on the minute-precision boundaries that will be stored. The database trigger
  # stays authoritative; this check turns the common conflict into a readable
  # error instead of an unexpected database failure.
  defp refute_overlap(changeset, opts) do
    case Session.list_overlapping(
           Ash.Changeset.get_attribute(changeset, :member_id),
           Ash.Changeset.get_attribute(changeset, :start_datetime),
           %{end_datetime: Ash.Changeset.get_attribute(changeset, :end_datetime)},
           opts
         ) do
      {:ok, []} ->
        changeset

      {:ok, overlapping} ->
        Ash.Changeset.add_error(
          changeset,
          InvalidAttribute.exception(
            field: :start_datetime,
            message: "overlaps existing sessions: %{sessions}",
            vars: [sessions: Enum.map_join(overlapping, "; ", &describe/1)]
          )
        )

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp describe(session) do
    ending =
      if session.end_datetime, do: DateTime.to_iso8601(session.end_datetime), else: "running"

    ~s("#{session.title}" #{session.id} #{DateTime.to_iso8601(session.start_datetime)} – #{ending})
  end
end
