defmodule Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob do
  @moduledoc """
  After updating an organization's avatar, destroys the previous blob
  (if any) from S3 and the database.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, organization ->
      old_blob_id = Ash.Changeset.get_data(changeset, :avatar_blob_id)

      if old_blob_id && old_blob_id != organization.avatar_blob_id do
        blob_opts = [tenant: organization.id, actor: context.actor]

        old_blob_id
        |> Blobs.get_blob!(blob_opts)
        |> Blobs.destroy_blob!(blob_opts)
      end

      {:ok, organization}
    end)
  end
end
