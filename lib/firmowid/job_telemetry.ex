defmodule Firmowid.JobTelemetry do
  @moduledoc "Logs background job attempts with allowlisted organization and operation context."

  require Logger

  @events [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]]

  @doc "Attaches the background job lifecycle logger once at application startup."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach, do: :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)

  @doc "Adds safe job context to worker logs and records the outcome of each attempt."
  @spec handle_event([atom()], map(), map(), nil) :: :ok
  def handle_event([:oban, :job, :start], _measurements, %{job: job}, nil) do
    Logger.metadata(Map.to_list(context(job)))
    Logger.info("Background job started", oban_state: :executing)
  end

  def handle_event([:oban, :job, event], %{duration: duration}, %{job: job, state: state}, nil)
      when event in [:stop, :exception] do
    metadata =
      job
      |> context()
      |> Map.merge(%{
        oban_state: state,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond)
      })
      |> Map.to_list()

    level = if event == :exception, do: :warning, else: :info
    Logger.log(level, "Background job finished", metadata)
  end

  @doc "Builds safe context for lifecycle logs and the existing Sentry Oban error integration."
  @spec context(Oban.Job.t()) :: map()
  def context(job) do
    Map.reject(
      %{
        organization_id: job.args["organization_id"] || job.args["tenant"] || job.meta["organization_id"],
        oban_job_id: job.id,
        oban_worker: job.worker,
        oban_queue: job.queue,
        oban_attempt: job.attempt,
        oban_max_attempts: job.max_attempts,
        stage: job.args["action"],
        subject_type: subject_type(job)
      },
      fn {_key, value} -> is_nil(value) end
    )
  end

  defp subject_type(%{worker: "Firmowid.Ash.Ksef.Workers.FetchWorker", args: args}),
    do: Map.get(args, "subject_type", "Subject2")

  defp subject_type(_job), do: nil
end
