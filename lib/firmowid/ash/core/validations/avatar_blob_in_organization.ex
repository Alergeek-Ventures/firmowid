defmodule Firmowid.Ash.Core.Validations.AvatarBlobInOrganization do
  @moduledoc """
  Ash validation that the member's new avatar blob belongs to the member's
  organization.
  """
  use Ash.Resource.Validation

  alias Firmowid.Ash.Blobs.Blob

  require Ash.Query

  @impl true
  def validate(changeset, _opts, context) do
    case Ash.Changeset.get_attribute(changeset, :avatar_blob_id) do
      nil ->
        :ok

      blob_id ->
        opts = Ash.Context.to_opts(context, tenant: changeset.data.organization_id)

        if Blob |> Ash.Query.filter(id == ^blob_id) |> Ash.exists?(opts) do
          :ok
        else
          {:error, field: :avatar_blob_id, message: "musi należeć do organizacji"}
        end
    end
  end
end
