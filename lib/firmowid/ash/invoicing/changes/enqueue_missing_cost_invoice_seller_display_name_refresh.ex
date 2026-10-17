defmodule Firmowid.Ash.Invoicing.Changes.EnqueueMissingCostInvoiceSellerDisplayNameRefresh do
  @moduledoc """
  Starts AshOban refresh trigger immediately for invoices without a seller display name.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if is_nil(record.seller_display_name) do
        AshOban.run_trigger(record, :refresh_missing_seller_display_name, tenant: record.organization_id)
      end

      {:ok, record}
    end)
  end
end
