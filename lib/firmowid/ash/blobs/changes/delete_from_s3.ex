defmodule Firmowid.Ash.Blobs.Changes.DeleteFromS3 do
  @moduledoc """
  Deletes the S3 object associated with a blob after the DB record is destroyed.

  Runs as an `after_action` hook on the destroy action. If S3 deletion fails,
  the error is logged but the destroy still succeeds — an orphaned S3 object
  is cheaper than an orphaned DB record, and S3 lifecycle policies can clean
  up stale objects.
  """
  use Ash.Resource.Change

  alias Firmowid.ErrorKind
  alias Firmowid.S3Client

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      case S3Client.delete_object(to_string(record.blob_path)) do
        {:ok, _} ->
          {:ok, record}

        {:error, reason} ->
          Logger.error("Failed to delete S3 object",
            blob_id: record.id,
            error_kind: ErrorKind.classify(reason)
          )

          {:ok, record}
      end
    end)
  end
end
