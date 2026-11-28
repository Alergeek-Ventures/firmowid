defmodule Firmowid.Blobs.Changes.UploadToS3 do
  @moduledoc """
  Preprocesses the uploaded file, computes a SHA-256 checksum, uploads to S3,
  and sets `blob_path`, `blob_checksum`, and `original_filename` on the changeset.

  The upload runs as a `before_action` hook, so it happens before the DB insert:
  if the upload fails, no orphaned record is created. The other way around, an
  `after_transaction` hook deletes the freshly uploaded object when the create
  then fails — a duplicate checksum hits the unique index only at the insert —
  so a failed create leaves no orphaned S3 object behind either. If that cleanup
  itself fails, the returned error carries the create's own error and the
  cleanup failure together.

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
    # The blob key the compensation must delete exists only after the upload
    # runs, but a hook registered inside a `before_action` is not called when
    # the action fails (Ash runs `after_transaction` hooks from the changeset
    # that entered the action, not the one the hook returned). The hook is
    # registered here instead, and the key is handed over through the process
    # dictionary: the action, the upload and its hooks run in one process. The
    # entry is put only after a successful upload, so it also marks that the
    # cleanup is needed at all.
    uploaded_key = {__MODULE__, make_ref()}

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      blob_id = Ash.Changeset.get_attribute(changeset, :id)

      upload_path = Ash.Changeset.get_argument(changeset, :upload_path)
      content_type = Ash.Changeset.get_argument(changeset, :content_type)
      original_filename = Ash.Changeset.get_argument(changeset, :original_filename)
      organization_id = changeset.tenant

      served_type = served_type(content_type, original_filename)
      {upload_path, blob_checksum} = UploadFingerprint.prepare_upload(upload_path, content_type)
      blob_path = "#{organization_id}/#{blob_id}.#{served_type |> MIME.extensions() |> hd()}"

      S3Client.upload_file!(upload_path, blob_path, content_type: sent_type(served_type))
      Process.put(uploaded_key, blob_path)

      changeset
      |> Ash.Changeset.force_change_attribute(:blob_path, blob_path)
      |> Ash.Changeset.force_change_attribute(:blob_checksum, blob_checksum)
      |> Ash.Changeset.force_change_attribute(:original_filename, original_filename)
    end)
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, _} = result ->
        Process.delete(uploaded_key)
        result

      _changeset, {:error, error} = result ->
        case Process.delete(uploaded_key) do
          nil -> result
          blob_path -> delete_uploaded_object(blob_path, error)
        end
    end)
  end

  # Only a 2xx response counts as deleted: Req hands S3 error responses (403,
  # 500) back as `{:ok, %Req.Response{}}` too, while S3 answers a successful
  # DELETE — also for a key that is already gone — with 204. A failed cleanup
  # is not swallowed, but must not drop the create's own error either (the
  # caller may still handle the duplicate checksum), so both end up in the
  # error class returned to the caller.
  defp delete_uploaded_object(blob_path, error) do
    case S3Client.delete_object(blob_path) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:error, error}

      {:ok, %Req.Response{status: status}} ->
        failed_cleanup(error, blob_path, {:http_status, status})

      {:error, reason} ->
        failed_cleanup(error, blob_path, reason)
    end
  end

  defp failed_cleanup(error, blob_path, reason) do
    cleanup_error =
      Ash.Error.Unknown.UnknownError.exception(
        error:
          "Failed to delete the S3 object (#{blob_path}) left behind by a failed blob upload: " <>
            inspect(reason)
      )

    {:error, Ash.Error.to_error_class([error, cleanup_error])}
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
