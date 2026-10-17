defmodule Firmowid.Ash.Delegations.Changes.CreateSignedSettlementBlob do
  @moduledoc "Stores the employee-signed settlement PDF and relates it to the delegation."

  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs

  @max_file_size 10 * 1024 * 1024

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with upload_path when is_binary(upload_path) <-
             Ash.Changeset.get_argument(changeset, :upload_path),
           :ok <- validate_size(upload_path),
           content_type when is_binary(content_type) <-
             Ash.Changeset.get_argument(changeset, :content_type),
           filename when is_binary(filename) <-
             Ash.Changeset.get_argument(changeset, :original_filename),
           {:ok, blob} <-
             Blobs.create_or_reuse_blob(upload_path, content_type, filename,
               actor: context.actor,
               tenant: context.tenant
             ) do
        Ash.Changeset.force_change_attribute(changeset, :signed_settlement_blob_id, blob.id)
      else
        nil ->
          Ash.Changeset.add_error(changeset,
            field: :upload_path,
            message: "Wybierz podpisany plik PDF."
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  # upload_path is allocated by Phoenix LiveView in its configured temporary upload directory.
  defp validate_size(upload_path) do
    case File.stat(upload_path) do
      {:ok, %{size: size}} when size <= @max_file_size -> :ok
      {:ok, _stat} -> {:error, "Plik może mieć maksymalnie 10 MB."}
      {:error, reason} -> {:error, reason}
    end
  end
end
