defmodule Firmowid.Ash.Delegations.Changes.CreateExpenseStatementBlob do
  @moduledoc "Creates and attaches a bank statement blob for a delegation expense."

  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs

  @impl true
  def change(changeset, _opts, context) do
    case Blobs.create_or_reuse_blob(
           Ash.Changeset.get_argument(changeset, :upload_path),
           Ash.Changeset.get_argument(changeset, :content_type),
           Ash.Changeset.get_argument(changeset, :original_filename),
           actor: context.actor,
           tenant: context.tenant
         ) do
      {:ok, blob} -> Ash.Changeset.force_change_attribute(changeset, :statement_blob_id, blob.id)
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end
end
