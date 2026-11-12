defmodule Firmowid.Blobs.Changes.UploadToS3 do
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

  alias Firmowid.Blobs.UploadFingerprint
  alias Firmowid.S3Client

  # The content type and the file name come from the client, and a LiveView upload
  # passes `accept` when either of them matches (`image/*` passes any `image/…`).
  # The type is sent with the object, since an S3 server left to guess may sniff
  # HTML from the content. Only passive document and image types the MIME table
  # knows are served as such; anything else is a download. XML can carry script:
  # the `+xml` types (SVG) are never passive, and `application/xml` keeps its
  # `.xml` path only under a name that says so and is sent as plain text: the
  # app reads KSeF invoices as text, and the storage server would turn a generic
  # type back into XML from the path's extension.
  @document_types [
    "application/pdf",
    "application/xml",
    "text/plain",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  ]

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      blob_id = Ash.Changeset.get_attribute(changeset, :id)

      upload_path = Ash.Changeset.get_argument(changeset, :upload_path)
      content_type = Ash.Changeset.get_argument(changeset, :content_type)
      original_filename = Ash.Changeset.get_argument(changeset, :original_filename)
      organization_id = changeset.tenant

      served_type = served_type(content_type, original_filename)
      {upload_path, blob_checksum} = UploadFingerprint.prepare_upload(upload_path, content_type)
      blob_path = "#{organization_id}/#{blob_id}.#{served_type |> MIME.extensions() |> hd()}"

      S3Client.upload_file!(upload_path, blob_path, content_type: sent_type(served_type))

      changeset
      |> Ash.Changeset.force_change_attribute(:blob_path, blob_path)
      |> Ash.Changeset.force_change_attribute(:blob_checksum, blob_checksum)
      |> Ash.Changeset.force_change_attribute(:original_filename, original_filename)
    end)
  end

  defp served_type(content_type, original_filename) do
    type = content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()

    cond do
      type == "application/xml" and String.downcase(Path.extname(original_filename)) != ".xml" ->
        "application/octet-stream"

      passive?(type) and MIME.extensions(type) != [] ->
        type

      true ->
        "application/octet-stream"
    end
  end

  defp sent_type("application/xml"), do: "text/plain"
  defp sent_type(type), do: type

  defp passive?(type) do
    (String.starts_with?(type, "image/") or type in @document_types) and
      not String.ends_with?(type, "+xml")
  end
end
