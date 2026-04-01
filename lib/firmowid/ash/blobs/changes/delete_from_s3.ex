defmodule Firmowid.Ash.Blobs.Changes.DeleteFromS3 do
  @moduledoc """
  Deletes the S3 object associated with a blob after the DB record is destroyed.

  Runs as an `after_action` hook on the destroy action. If S3 deletion fails,
  the error is logged but the destroy still succeeds — an orphaned S3 object
  is cheaper than an orphaned DB record, and S3 lifecycle policies can clean
  up stale objects.
  """
  use Ash.Resource.Change

  alias ExAws.S3

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      bucket =
        :firmowid
        |> Application.get_env(:uploads_bucket)
        |> to_string()

      case bucket |> S3.delete_object(to_string(record.blob_path)) |> ExAws.request() do
        {:ok, _} ->
          {:ok, record}

        {:error, reason} ->
          Logger.error("Failed to delete S3 object #{record.blob_path}: #{inspect(reason)}")
          {:ok, record}
      end
    end)
  end
end
