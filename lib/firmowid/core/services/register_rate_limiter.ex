defmodule Firmowid.Core.Services.RegisterRateLimiter do
  @moduledoc """
  Keeps the request limits of CEIDG and the VAT white list for the whole node.
  Every process asks here before a request, so parallel sessions, Oban jobs and
  organizations share one budget, as the registers count it per IP address.

  CEIDG requests are spaced evenly: a caller waits for its turn, or is refused
  when the queue is longer than the register's `max_wait_ms`. The white list's daily
  quotas are counted per Warsaw day and refused once used up. The count lives in
  memory: a restart starts it from zero. The app runs on a single node
  (no `dns_cluster_query` is configured), so one process holds the whole budget.
  """
  use GenServer

  @type register :: :ceidg | :mf_search | :mf_status

  @limits Application.compile_env(:firmowid, :register_rate_limits, %{
            # CEIDG allows 50 requests in 3 minutes and 1000 an hour, and blocks for 3 minutes
            # when exceeded; one request every 3.7 s keeps under both.
            ceidg: %{every_ms: 3_700, max_wait_ms: 30_000},
            # The white list allows a day 100 `search` requests of up to 30 NIPs and 50 000 WL2
            # status requests, and may block the IP for search until midnight once exceeded.
            mf_search: %{per_day: 100},
            mf_status: %{per_day: 50_000}
          })

  @doc "Starts the limiter; `:limits` and `:name` default to the app's registers and module name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.get(opts, :limits, @limits), name: name)
  end

  @doc """
  Takes one request of `register`'s limit: returns `:ok` once the request may be
  sent, or `{:error, :rate_limited}` when the limit does not allow it now.
  """
  @spec acquire(register(), GenServer.server()) :: :ok | {:error, :rate_limited}
  def acquire(register, server \\ __MODULE__) do
    # The limiter answers within the register's `max_wait_ms`.
    GenServer.call(server, {:acquire, register}, :infinity)
  end

  @impl GenServer
  def init(limits), do: {:ok, %{limits: limits, counters: %{}}}

  @impl GenServer
  def handle_call({:acquire, register}, from, state) do
    take_turn(register, Map.fetch!(state.limits, register), from, state)
  end

  defp take_turn(register, %{every_ms: every_ms, max_wait_ms: max_wait_ms}, from, state) do
    now = System.monotonic_time(:millisecond)
    turn = max(now, Map.get(state.counters, register, now))
    state_after_turn = put_in(state.counters[register], turn + every_ms)

    cond do
      turn - now > max_wait_ms ->
        {:reply, {:error, :rate_limited}, state}

      turn == now ->
        {:reply, :ok, state_after_turn}

      true ->
        Process.send_after(self(), {:release, from}, turn - now)
        {:noreply, state_after_turn}
    end
  end

  defp take_turn(register, %{per_day: per_day}, _from, state) do
    today = "Europe/Warsaw" |> DateTime.now!() |> DateTime.to_date()

    case Map.get(state.counters, register) do
      {^today, used} when used >= per_day -> {:reply, {:error, :rate_limited}, state}
      {^today, used} -> {:reply, :ok, put_in(state.counters[register], {today, used + 1})}
      _earlier_day_or_none -> {:reply, :ok, put_in(state.counters[register], {today, 1})}
    end
  end

  @impl GenServer
  def handle_info({:release, from}, state) do
    GenServer.reply(from, :ok)
    {:noreply, state}
  end
end
