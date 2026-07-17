defmodule Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob do
  @moduledoc """
  After updating an avatar owner, destroys the previous blob (if any)
  from S3 and the database.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      old_blob_id = Ash.Changeset.get_data(changeset, :avatar_blob_id)

      if old_blob_id && old_blob_id != record.avatar_blob_id &&
           avatar_blob_unreferenced?(old_blob_id, record, context) do
        tenant = Map.get(record, :organization_id, record.id)

        # Used SystemActor to bypass authorization checks for blob deletion, since the blob is no longer referenced by any user or organization
        # and user lacks permission to delete it.
        scope = %Scope{
          actor: %SystemActor{org_id: tenant, role: :avatar_cleanup},
          tenant: tenant
        }

        old_blob_id
        |> Blobs.get_blob!(scope: scope)
        |> Blobs.destroy_blob!(scope: scope)
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
