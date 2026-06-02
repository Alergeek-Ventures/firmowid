defmodule Firmowid.Ash.Blobs.Changes.EnqueueDocumentBlobProcessing do
  @moduledoc """
  Starts AshOban processing trigger immediately for document blobs.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if record.processing_target != :none and record.processing_state == :pending do
        AshOban.run_trigger(record, :process_document_blobs, tenant: record.organization_id)
      end

      {:ok, record}
    end)
  end
end
