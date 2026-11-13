defmodule Firmowid.Blobs.PictureVariants do
  @moduledoc """
  Small WebP copies of a picture (a member's or an organization's avatar) and
  its inline placeholder.

  Pages show avatars at 24–128 px, so they load one of these instead of the
  original, which keeps up to 1000 px. The copies sit in storage next to the
  original under keys derived from the blob; the placeholder, a WebP a few
  pixels wide as a data URI, is kept on the blob and shown blurred while a copy
  loads.
  """

  alias Firmowid.Blobs.Blob

  @widths [96, 256]
  @placeholder_width 8
  @write_options [suffix: ".webp", strip_metadata: true]
  # The bound uploads have (`Firmowid.Blobs.UploadFingerprint`); a picture stored
  # under a type they do not shrink is decoded here without it otherwise.
  @max_decoded_image_bytes 256 * 1024 * 1024

  @doc "The widths of the stored copies, smallest first."
  @spec widths() :: [pos_integer()]
  def widths, do: @widths

  @doc "The storage key of the blob's copy at `width`."
  @spec object_key(Blob.t(), pos_integer()) :: String.t()
  def object_key(%Blob{} = blob, width) when width in @widths, do: "#{blob.organization_id}/#{blob.id}-#{width}.webp"

  @doc """
  Encodes the copies of a picture, keyed by width, and its placeholder.

  The shorter side of each copy is the width, so it stays sharp both when an
  avatar crops it to a square and when a logo fits it inside one. Pictures are
  never enlarged.
  """
  @spec build(binary()) :: {:ok, %{pos_integer() => binary()}, String.t()} | {:error, term()}
  def build(original) do
    with {:ok, image} <- Image.from_binary(original),
         :ok <- check_decoded_size(image),
         {:ok, copies} <- encode_copies(image),
         {:ok, placeholder} <- placeholder(copies[hd(@widths)]) do
      {:ok, copies, placeholder}
    end
  end

  defp check_decoded_size(image) do
    {_kind, bits_per_band} = Image.band_format(image)

    decoded_bytes =
      Image.width(image) * Image.height(image) * Image.bands(image) * div(bits_per_band, 8)

    if decoded_bytes > @max_decoded_image_bytes, do: {:error, :image_too_large}, else: :ok
  end

  defp encode_copies(image) do
    Enum.reduce_while(@widths, {:ok, %{}}, fn width, {:ok, copies} ->
      case encode_copy(image, width) do
        {:ok, webp} -> {:cont, {:ok, Map.put(copies, width, webp)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp encode_copy(image, width) do
    sides = [Image.width(image), Image.height(image)]
    # A thumbnail's length is its longer side.
    length = ceil(Enum.max(sides) * width / Enum.min(sides))

    with {:ok, resized} <- Image.thumbnail(image, length, resize: :down) do
      Image.write(resized, :memory, @write_options)
    end
  end

  # Built from the smallest copy: decoding it is cheaper than the original.
  defp placeholder(webp) do
    with {:ok, image} <- Image.from_binary(webp),
         {:ok, tiny} <- Image.thumbnail(image, @placeholder_width),
         {:ok, tiny_webp} <- Image.write(tiny, :memory, @write_options) do
      {:ok, "data:image/webp;base64," <> Base.encode64(tiny_webp)}
    end
  end
end
