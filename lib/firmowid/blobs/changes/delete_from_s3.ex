defmodule Firmowid.Blobs.Changes.DeleteFromS3 do
  @moduledoc """
  Deletes the S3 object associated with a blob, and a picture's small copies
  (`Firmowid.Blobs.PictureVariants`), after the DB record is destroyed.

  Runs as an `after_action` hook on the destroy action. If S3 deletion fails,
  the error is logged but the destroy still succeeds — an orphaned S3 object
  is cheaper than an orphaned DB record, and S3 lifecycle policies can clean
  up stale objects.
  """
  use Ash.Resource.Change

  alias Firmowid.Blobs.PictureVariants
  alias Firmowid.ErrorKind
  alias Firmowid.S3Client

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      record |> object_keys() |> Enum.each(&delete_object(record, &1))
      {:ok, record}
    end)
  end

  # Copies may exist without a placeholder (an upload that failed halfway); deleting a
  # missing key is harmless, so every blob tries them.
  defp object_keys(record),
    do: [to_string(record.blob_path) | Enum.map(PictureVariants.widths(), &PictureVariants.object_key(record, &1))]

  defp delete_object(record, key) do
    case S3Client.delete_object(key) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete S3 object",
          blob_id: record.id,
          error_kind: ErrorKind.classify(reason)
        )
    end
  end
end
