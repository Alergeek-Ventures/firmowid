defmodule Firmowid.Ash.Blobs.Changes.EnqueueCostInvoiceBlobProcessing do
  @moduledoc """
  Starts AshOban processing trigger immediately for cost invoice blobs.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if record.processing_target == :cost_invoice and record.processing_state == :pending do
        AshOban.run_trigger(record, :process_cost_invoice, tenant: record.organization_id)
      end

      {:ok, record}
    end)
  end
end
