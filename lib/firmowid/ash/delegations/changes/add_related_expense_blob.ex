defmodule Firmowid.Ash.Delegations.Changes.AddRelatedExpenseBlob do
  @moduledoc "Creates a blob and attaches it as a supporting expense document."

  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs

  @impl true
  def change(changeset, _opts, context) do
    upload_path = Ash.Changeset.get_argument(changeset, :upload_path)
    content_type = Ash.Changeset.get_argument(changeset, :content_type)
    filename = Ash.Changeset.get_argument(changeset, :original_filename)

    case Blobs.create_or_reuse_blob(upload_path, content_type, filename,
           actor: context.actor,
           tenant: context.tenant
         ) do
      {:ok, blob} ->
        Ash.Changeset.manage_relationship(changeset, :related_blobs, [blob], type: :append)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end
end
