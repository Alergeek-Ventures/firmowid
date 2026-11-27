defmodule Firmowid.Taxes.Forecast.Recalculation do
  @moduledoc """
  Queues the recalculation of an organization's saved tax forecasts: the job of the daily
  `:save_forecasts` scheduled action for this one tenant, computed and applied by the same
  worker and the same system actor as in the daily run.

  A job that is already running may have read old data, so only a job still waiting stands in
  for a new one. Uniqueness ignores `scheduled_at` (`Oban.Job` checks `inserted_at` against the
  period, here `:infinity`), so a delayed job waiting in `:scheduled` absorbs every request until
  it runs.
  """
  alias Firmowid.Taxes.TaxYear

  # A bank sync of hundreds of rows or a KSeF import ends in one recalculation.
  @debounce_seconds 60

  @doc "Queues the recalculation to run at once."
  @spec now(Ash.UUID.t()) :: :ok
  def now(tenant), do: insert(tenant, [])

  @doc """
  Queues the recalculation to run in a minute, for a change of the data the forecast reads. Does
  nothing in tests with Oban in the `:inline` mode, which would run it at once, on every invoice
  or transaction a test writes; tests of the queueing switch to `:manual`.
  """
  @spec later(Ash.UUID.t()) :: :ok
  def later(tenant) do
    # `get_engine/1` is internal to Oban, but the only place that knows the testing mode of the process.
    if Oban.Config.get_engine(Oban.config(Oban)) == Oban.Engines.Inline,
      do: :ok,
      else: insert(tenant, schedule_in: @debounce_seconds)
  end

  # The args a tenant's job of the daily run has: AshOban's worker fans a tenantless job out into these.
  defp insert(tenant, opts) do
    %{worker: worker} = AshOban.Info.oban_scheduled_action(TaxYear, :save_forecasts)

    %{"tenant" => tenant}
    |> worker.new(
      [unique: [period: :infinity, keys: [:tenant], states: [:available, :scheduled, :retryable]]] ++
        opts
    )
    |> Firmowid.Oban.insert!(organization_id: tenant)

    :ok
  end
end
