defmodule Firmowid.Blobs.Changes.GeneratePictureVariants do
  @moduledoc """
  Stores the small copies of a picture (`Firmowid.Blobs.PictureVariants`) and
  sets its placeholder, which tells pages that the copies exist.

  The copies are uploaded before the placeholder is saved, so a page never
  points at a copy that is not there yet.
  """
  use Ash.Resource.Change

  alias Firmowid.Blobs.PictureVariants
  alias Firmowid.S3Client

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      blob = changeset.data

      with {:ok, original} <- S3Client.get_object(blob.blob_path),
           {:ok, copies, placeholder} <- PictureVariants.build(original),
           :ok <- upload(blob, copies) do
        Ash.Changeset.force_change_attribute(changeset, :placeholder, placeholder)
      else
        {:error, reason} ->
          Ash.Changeset.add_error(
            changeset,
            "Generating picture variants failed: #{inspect(reason)}"
          )
      end
    end)
  end

  defp upload(blob, copies) do
    Enum.reduce_while(copies, :ok, fn {width, webp}, :ok ->
      case S3Client.upload_binary!(webp, PictureVariants.object_key(blob, width), content_type: "image/webp") do
        %Req.Response{status: 200} -> {:cont, :ok}
        %Req.Response{status: status} -> {:halt, {:error, {:upload_http_status, status}}}
      end
    end)
  end
end
