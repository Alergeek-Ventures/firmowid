defmodule Firmowid.Ash.Payroll.Validations.SourceBlobInOrganization do
  @moduledoc "Keeps a payroll source document inside the record's organization."
  use Ash.Resource.Validation

  alias Firmowid.Ash.Blobs

  @impl true
  def validate(changeset, _opts, context) do
    source_blob_id = Ash.Changeset.get_attribute(changeset, :source_blob_id)
    opts = Ash.Context.to_opts(context, tenant: changeset.tenant, not_found_error?: false)

    case Blobs.get_blob(source_blob_id, opts) do
      {:ok, nil} -> {:error, field: :source_blob_id, message: "is invalid"}
      {:ok, _blob} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
