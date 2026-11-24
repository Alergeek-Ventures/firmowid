defmodule Firmowid.Blobs.Validations.NotDocumentBlob do
  @moduledoc """
  Ash validation that the file an avatar action attaches is not a document.

  The whole organization reads an avatar, so a document file set as one would
  be readable by members its owner record hides it from. The check sees every
  record holding the file, also those the actor cannot read.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Blobs.Blob
  alias Firmowid.SystemActor

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :avatar_blob_id) do
      nil -> :ok
      blob_id -> check(blob_id, organization_id(changeset.data))
    end
  end

  defp check(blob_id, organization_id) do
    actor = %SystemActor{org_id: organization_id, role: :avatar_cleanup, blob_id: blob_id}

    case Blob
         |> Ash.Query.filter(id == ^blob_id and document?)
         |> Ash.exists(actor: actor, tenant: organization_id) do
      {:ok, false} ->
        :ok

      {:ok, true} ->
        {:error, field: :avatar_blob_id, message: gettext_noop("is a document, not a picture")}

      {:error, error} ->
        {:error, error}
    end
  end

  # Avatars belong to a member or to the organization itself.
  defp organization_id(%{organization_id: organization_id}), do: organization_id
  defp organization_id(%{id: organization_id}), do: organization_id
end
