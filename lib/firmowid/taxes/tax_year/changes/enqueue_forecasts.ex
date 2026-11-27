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
  alias Firmowid.Taxes.Forecast.Recalculation

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_transaction(changeset, fn
      %{tenant: tenant}, {:ok, _tax_year} = result ->
        Recalculation.now(tenant)
        result

      _changeset, result ->
        result
    end)
  end
end
