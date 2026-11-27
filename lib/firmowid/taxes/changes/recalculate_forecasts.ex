defmodule Firmowid.Taxes.Changes.RecalculateForecasts do
  @moduledoc """
  Queues the recalculation of the organization's saved tax forecasts after an action wrote data
  the forecast reads (see `Firmowid.Taxes.Forecast.Recalculation`).

  It runs after the transaction, so the job reads the committed data, and queues nothing when
  the action failed. A queueing failure raises after the write has been committed, as for a tax
  year's own save. On the organization itself the tenant is its id.
  """
  use Ash.Resource.Change

  alias Ash.Changeset
  alias Firmowid.Taxes.Forecast.Recalculation

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_transaction(changeset, fn
      changeset, {:ok, record} = result ->
        Recalculation.later(changeset.tenant || record.id)
        result

      _changeset, result ->
        result
    end)
  end

  # Only a hook after the transaction, so atomic updates (a plain `update_internal_note`) keep working.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
