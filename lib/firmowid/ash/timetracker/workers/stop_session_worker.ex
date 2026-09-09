defmodule Firmowid.Ash.Timetracker.Workers.StopSessionWorker do
  @moduledoc """
  Caps a forgotten running session at 12 hours.

  Enqueued when a session is started; when it fires, sets `end_datetime` to
  `start_datetime + 12 hours` if the session is still open. Manual sessions
  with an explicit end are not affected.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.Session
  alias Firmowid.Oban, as: FirmowidOban

  require Logger

  @max_running_hours 12

  @doc "Maximum allowed duration for an automatically capped running session."
  @spec max_running_seconds() :: pos_integer()
  def max_running_seconds, do: @max_running_hours * 3600

  @doc "Schedules an auto-stop for a running session at start + 12 hours."
  @spec enqueue(Session.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(%Session{} = session) do
    scheduled_at =
      session.start_datetime
      |> DateTime.shift(second: max_running_seconds())
      |> DateTime.shift_zone!("Etc/UTC")

    %{
      "session_id" => session.id,
      "organization_id" => session.organization_id
    }
    |> new(scheduled_at: scheduled_at)
    |> FirmowidOban.insert(organization_id: session.organization_id)
  end

  @doc "Cancels pending auto-stop jobs for the given session."
  @spec cancel(Ash.UUID.t()) :: {:ok, non_neg_integer()}
  def cancel(session_id) when is_binary(session_id) do
    FirmowidOban.cancel_all_jobs(
      from(j in Oban.Job,
        where:
          j.worker == "Firmowid.Ash.Timetracker.Workers.StopSessionWorker" and
            j.state in ["available", "scheduled", "retryable"] and
            fragment("?->>'session_id' = ?", j.args, ^session_id)
      )
    )
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    session_id = args["session_id"]
    organization_id = args["organization_id"]
    scope = scope(organization_id)

    Logger.info("Auto-stopping session session_id=#{session_id} attempt=#{job.attempt}/#{job.max_attempts}")

    case Timetracker.get_session_by_id(session_id, scope: scope, not_found_error?: false) do
      {:ok, nil} ->
        Logger.info("Session not found for auto-stop session_id=#{session_id}")
        :ok

      {:ok, %{end_datetime: end_datetime}} when not is_nil(end_datetime) ->
        Logger.info("Session already stopped session_id=#{session_id}")
        :ok

      {:ok, session} ->
        auto_stop(session, scope)

      {:error, reason} ->
        Logger.error("Failed to load session for auto-stop session_id=#{session_id} reason=#{inspect(reason)}")

        {:error, reason}
    end
  end

  defp auto_stop(session, scope) do
    case Session.auto_stop(session, scope: scope) do
      {:ok, _session} ->
        Logger.info("Auto-stopped session session_id=#{session.id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to auto-stop session session_id=#{session.id} reason=#{inspect(reason)}")

        {:error, reason}
    end
  end

  defp scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :session_auto_stopper},
      tenant: organization_id
    }
  end
end
