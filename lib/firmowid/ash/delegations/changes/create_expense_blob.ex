defmodule Firmowid.Ash.Delegations.Changes.CreateExpenseBlob do
  @moduledoc "Creates a durable blob for an uploaded delegation expense document."

  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs

  @impl true
  def change(changeset, _opts, context) do
    with upload_path when is_binary(upload_path) <-
           Ash.Changeset.get_argument(changeset, :upload_path),
         content_type when is_binary(content_type) <-
           Ash.Changeset.get_argument(changeset, :content_type),
         filename when is_binary(filename) <-
           Ash.Changeset.get_attribute(changeset, :original_filename),
         {:ok, blob} <-
           Blobs.create_or_reuse_blob(upload_path, content_type, filename,
             actor: context.actor,
             tenant: context.tenant
           ) do
      Ash.Changeset.force_change_attribute(changeset, :blob_id, blob.id)
    else
      nil -> changeset
      error -> Ash.Changeset.add_error(changeset, error)
    end
  end
end
