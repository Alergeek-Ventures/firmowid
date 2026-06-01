defmodule Firmowid.Ash.Blobs.Changes.EnqueueEmploymentContractBlobProcessing do
  @moduledoc """
  Starts AshOban processing trigger immediately for employment contracts blobs.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if record.processing_target == :employment_contract and record.processing_state == :pending do
        AshOban.run_trigger(record, :process_employment_contract, tenant: record.organization_id)
      end

      {:ok, record}
    end)
  end
end
