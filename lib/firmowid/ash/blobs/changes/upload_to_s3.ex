defmodule Firmowid.Ash.Blobs.Changes.UploadToS3 do
  @moduledoc """
  Preprocesses the uploaded file, computes a SHA-256 checksum, uploads to S3,
  and sets `blob_path`, `blob_checksum`, and `original_filename` on the changeset.

  Runs as a `before_action` hook so that S3 upload happens before the DB insert —
  if the upload fails, no orphaned record is created.

  Expects the changeset to carry three arguments:

    * `:upload_path` — local path to the file (temp file from Briefly or Phoenix)
    * `:content_type` — MIME type string
    * `:original_filename` — user-facing file name
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs.UploadFingerprint
  alias Firmowid.S3Client

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      blob_id = Ash.Changeset.get_attribute(changeset, :id)

      upload_path = Ash.Changeset.get_argument(changeset, :upload_path)
      content_type = Ash.Changeset.get_argument(changeset, :content_type)
      original_filename = Ash.Changeset.get_argument(changeset, :original_filename)
      organization_id = changeset.tenant

      extension = content_type |> MIME.extensions() |> List.first("bin")
      {upload_path, blob_checksum} = UploadFingerprint.prepare_upload(upload_path, content_type)
      blob_path = "#{organization_id}/#{blob_id}.#{extension}"

      upload_to_s3!(upload_path, blob_path)

      changeset
      |> Ash.Changeset.force_change_attribute(:blob_path, blob_path)
      |> Ash.Changeset.force_change_attribute(:blob_checksum, blob_checksum)
      |> Ash.Changeset.force_change_attribute(:original_filename, original_filename)
    end)
  end

  defp upload_to_s3!(upload_path, blob_path) do
    S3Client.upload_file!(upload_path, blob_path)
  end
end
