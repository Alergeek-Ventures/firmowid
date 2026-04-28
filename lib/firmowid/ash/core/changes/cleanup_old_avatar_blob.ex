defmodule Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob do
  @moduledoc """
  After updating an avatar owner, destroys the previous blob (if any)
  from S3 and the database.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Core.User

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      old_blob_id = Ash.Changeset.get_data(changeset, :avatar_blob_id)

      if old_blob_id && old_blob_id != record.avatar_blob_id &&
           avatar_blob_unreferenced?(old_blob_id, record, context) do
        tenant = Map.get(record, :organization_id, record.id)
        blob_opts = [tenant: tenant, actor: context.actor]

        old_blob_id
        |> Blobs.get_blob!(blob_opts)
        |> Blobs.destroy_blob!(blob_opts)
      end

      {:ok, record}
    end)
  end

  defp avatar_blob_unreferenced?(blob_id, record, context) do
    opts = [tenant: Map.get(record, :organization_id, record.id), actor: context.actor]

    not user_references_blob?(blob_id, opts) and not organization_references_blob?(blob_id, opts)
  end

  defp user_references_blob?(blob_id, opts) do
    User
    |> Ash.Query.filter(avatar_blob_id == ^blob_id)
    |> Ash.Query.for_read(:read, %{}, opts)
    |> Ash.exists?(opts)
  end

  defp organization_references_blob?(blob_id, opts) do
    Organization
    |> Ash.Query.filter(avatar_blob_id == ^blob_id)
    |> Ash.Query.for_read(:read, %{}, opts)
    |> Ash.exists?(opts)
  end
end
