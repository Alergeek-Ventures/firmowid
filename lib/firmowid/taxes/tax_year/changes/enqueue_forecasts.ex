defmodule Firmowid.Taxes.TaxYear.Changes.EnqueueForecasts do
  @moduledoc """
  Recalculates the organization's saved tax forecasts once a tax year is saved, instead of
  leaving the payments as they were until the next daily run.

  It queues the job of the daily `:save_forecasts` scheduled action for this one tenant, so the
  forecasts are computed and applied by the same worker and the same system actor as in the
  daily run. The job is queued after the transaction, so it reads the committed settings and
  partners, and a forecast that cannot be computed fails the job (and its retries), never the
  save. An error that rolled the save back queues nothing.
  """
  use Ash.Resource.Change

  alias Ash.Changeset
  alias Firmowid.Taxes.TaxYear

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_transaction(changeset, fn
      %{tenant: tenant}, {:ok, _tax_year} = result ->
        enqueue(tenant)
        result

      _changeset, result ->
        result
    end)
  end

  # The args a tenant's job of the daily run has: AshOban's worker fans a tenantless job out into these.
  # A job that is already running may have read the settings before this save, so only a job
  # still waiting stands in for a new one.
  defp enqueue(tenant) do
    %{worker: worker} = AshOban.Info.oban_scheduled_action(TaxYear, :save_forecasts)

    %{"tenant" => tenant}
    |> worker.new(unique: [period: :infinity, keys: [:tenant], states: [:available, :scheduled, :retryable]])
    |> Firmowid.Oban.insert!(organization_id: tenant)
  end
end
