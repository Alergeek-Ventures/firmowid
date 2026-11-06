defmodule Firmowid.Delegations.Changes.CreateSignedCommandBlob do
  @moduledoc "Creates a durable blob for an employer-signed business trip order."

  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Blobs
  alias Firmowid.Delegations.CommandUpload

  @impl true
  def change(changeset, _opts, context) do
    with upload_path when is_binary(upload_path) <-
           Ash.Changeset.get_argument(changeset, :upload_path),
         content_type when is_binary(content_type) <-
           Ash.Changeset.get_argument(changeset, :content_type),
         filename when is_binary(filename) <-
           Ash.Changeset.get_attribute(changeset, :signed_command_filename),
         {:ok, prepared_path} <- CommandUpload.prepare(upload_path),
         {:ok, blob} <-
           create_blob(prepared_path, upload_path, content_type, filename, context) do
      Ash.Changeset.force_change_attribute(changeset, :signed_command_blob_id, blob.id)
    else
      nil ->
        changeset

      {:error, reason} when reason in [:too_large, :signed, :cannot_compress] ->
        Ash.Changeset.add_error(changeset, field: :upload_path, message: upload_error(reason))

      error ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  # prepared_path, when different, was allocated by Briefly in CommandUpload.
  defp create_blob(prepared_path, original_path, content_type, filename, context) do
    Blobs.create_or_reuse_blob(prepared_path, content_type, filename,
      actor: context.actor,
      tenant: context.tenant
    )
  after
    if prepared_path != original_path, do: File.rm!(prepared_path)
  end

  defp upload_error(:too_large),
    do: gettext_noop("The order must fit within 8 MB. Choose a PDF up to 32 MB for automatic lossless compression.")

  defp upload_error(:signed),
    do:
      gettext_noop(
        "This PDF has an electronic signature and exceeds 8 MB. Compression would invalidate the signature. Reduce the file before signing, then upload it again. Your order details are saved."
      )

  defp upload_error(:cannot_compress),
    do:
      gettext_noop(
        "Could not safely reduce this PDF to 8 MB. Choose an unprotected PDF or scan it again with a smaller file size. Your order details are saved."
      )
end
