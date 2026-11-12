defmodule Firmowid.Blobs.Validations.ReadableBlob do
  @moduledoc """
  Ash validation that the actor may read the stored file the action attaches.

  A member reads a file through the record that holds it, so attaching a file
  the actor cannot read to their own record would expose it. The check reads
  the blob as the actor, with the Blob read policy.

  ## Options

  - `attribute` — the attribute holding the blob id (default `:avatar_blob_id`)
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Blobs.Blob

  require Ash.Query

  @impl true
  def validate(changeset, opts, context) do
    attribute = Keyword.get(opts, :attribute, :avatar_blob_id)

    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil ->
        :ok

      blob_id ->
        case Blob
             |> Ash.Query.filter(id == ^blob_id)
             |> Ash.exists(Ash.Context.to_opts(context)) do
          {:ok, true} ->
            :ok

          {:ok, false} ->
            {:error, field: attribute, message: gettext_noop("must belong to the organization")}

          {:error, error} ->
            {:error, error}
        end
    end
  end
end
