defmodule Firmowid.Ash.Invoicing.Changes.EnqueueKsefInvoiceDigestSend do
  @moduledoc """
  Starts AshOban delivery immediately for newly created KSeF invoice digests.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if Ash.Changeset.get_argument(changeset, :enqueue_send?) == false do
        {:ok, record}
      else
        actor = %Firmowid.Ash.SystemActor{org_id: record.organization_id, role: :ksef_digest}
        AshOban.run_trigger(record, :send_digest, tenant: record.organization_id, actor: actor)
        {:ok, record}
      end
    end)
  end
end
