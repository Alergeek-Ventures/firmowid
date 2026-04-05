defmodule Firmowid.Ash.Ksef.KsefAwarePruner do
  @moduledoc """
  Custom Oban pruner that preserves KSeF submission jobs.

  This plugin extends the standard `Oban.Plugins.Pruner` behavior but excludes
  jobs from the `ksef_submissions` queue. This is necessary because:

  1. KSeF submission history is used to display error states in the UI
  2. The `Ksef.submission_failed?/1` function queries discarded jobs to show failures
  3. Users need to see the submission history for troubleshooting

  ## Usage

  Replace the standard Pruner in your Oban config:

      plugins: [
        {Firmowid.Ash.Ksef.KsefAwarePruner, max_age: 60 * 60 * 24 * 30},
        ...
      ]

  ## Options

  Same as `Oban.Plugins.Pruner`:

  * `:interval` — milliseconds between pruning attempts. Default: 30_000ms.
  * `:limit` — maximum jobs to prune at once. Default: 10_000.
  * `:max_age` — seconds after which a job may be pruned. Default: 60s.
  """

  @behaviour Oban.Plugin

  use GenServer

  import Ecto.Query

  alias Oban.Job
  alias Oban.Peer
  alias Oban.Plugin
  alias Oban.Repo
  alias Oban.Validation

  require Logger

  @excluded_queues ["ksef_submissions"]

  @type option ::
          Plugin.option()
          | {:interval, pos_integer()}
          | {:limit, pos_integer()}
          | {:max_age, pos_integer()}

  defstruct [
    :conf,
    :timer,
    interval: to_timeout(second: 30),
    limit: 10_000,
    max_age: 60
  ]

  @doc false
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts), do: super(opts)

  @impl Plugin
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(__MODULE__, opts), name: name)
  end

  @impl Plugin
  def validate(opts) do
    Validation.validate_schema(opts,
      conf: :any,
      name: :any,
      interval: :pos_integer,
      limit: :pos_integer,
      max_age: :pos_integer
    )
  end

  @impl Plugin
  def format_logger_output(_conf, meta), do: Map.take(meta, [:pruned_count])

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    :telemetry.execute([:oban, :plugin, :init], %{}, %{conf: state.conf, plugin: __MODULE__})

    {:ok, schedule_prune(state)}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    :ok
  end

  @impl GenServer
  def handle_info(:prune, state) do
    meta = %{conf: state.conf, plugin: __MODULE__}

    :telemetry.span([:oban, :plugin], meta, fn ->
      case check_leadership_and_delete_jobs(state) do
        {:ok, extra} when is_map(extra) ->
          {:ok, Map.merge(meta, extra)}

        error ->
          {:error, Map.put(meta, :error, error)}
      end
    end)

    {:noreply, schedule_prune(state)}
  end

  def handle_info(message, state) do
    Logger.warning(
      message: "Received unexpected message: #{inspect(message)}",
      source: :oban,
      module: __MODULE__
    )

    {:noreply, state}
  end

  defp schedule_prune(state) do
    %{state | timer: Process.send_after(self(), :prune, state.interval)}
  end

  defp check_leadership_and_delete_jobs(state) do
    if Peer.leader?(state.conf) do
      Repo.transaction(state.conf, fn ->
        {:ok, jobs} = prune_jobs(state.conf, state.limit, state.max_age)

        %{pruned_count: length(jobs), pruned_jobs: jobs}
      end)
    else
      {:ok, %{pruned_count: 0, pruned_jobs: []}}
    end
  end

  defp prune_jobs(conf, limit, max_age) do
    time = DateTime.add(DateTime.utc_now(), -max_age)

    subquery =
      Job
      |> select([:id, :queue, :state])
      |> where([j], j.state == "completed" and j.scheduled_at < ^time)
      |> or_where([j], j.state == "cancelled" and j.cancelled_at < ^time)
      |> or_where([j], j.state == "discarded" and j.discarded_at < ^time)
      |> where([j], not is_nil(j.queue))
      # Exclude KSeF submission jobs from pruning
      |> where([j], j.queue not in ^@excluded_queues)
      |> limit(^limit)

    query =
      Job
      |> join(:inner, [j], x in subquery(subquery), on: j.id == x.id)
      |> select([_, x], map(x, [:id, :queue, :state]))

    {_count, pruned} = Repo.delete_all(conf, query)

    {:ok, pruned}
  end
end
