defmodule Firmowid.Ash.Invoicing.Changes.EnqueueMissingCostInvoiceDescriptionRefresh do
  @moduledoc """
  Starts AshOban refresh trigger immediately for invoices with empty description.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if record.description == "" do
        AshOban.run_trigger(record, :refresh_missing_description, tenant: record.organization_id)
      end

      {:ok, record}
    end)
  end
end
