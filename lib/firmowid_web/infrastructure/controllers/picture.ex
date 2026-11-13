defmodule FirmowidWeb.Infrastructure.Controllers.Picture do
  @moduledoc """
  Serves the small copies of an avatar (`Firmowid.Blobs.PictureVariants`) from
  the private bucket to members who may read the picture.

  A blob's bytes never change: a new picture is a new blob, and a blob reused
  for an identical upload holds the same bytes. So browsers may keep a copy for
  a year instead of fetching it on every page, which presigned URLs, new on
  every render, never allowed.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Blobs
  alias Firmowid.Blobs.PictureVariants
  alias Firmowid.S3Client

  @doc "Sends the picture's copy at the requested width, or 404."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id, "width" => width}) do
    with width when is_integer(width) <-
           Enum.find(PictureVariants.widths(), &(Integer.to_string(&1) == width)),
         {:ok, %{placeholder: placeholder} = blob} when is_binary(placeholder) <-
           Blobs.get_blob(id, scope: conn.assigns.ash_scope) do
      # The placeholder is saved only after the copies are stored.
      {:ok, webp} = S3Client.get_object(PictureVariants.object_key(blob, width))
      send_picture(conn, webp)
    else
      # An unknown width, a picture without copies yet, or an id that is malformed, missing
      # or another organization's; any other failure crashes and is reported.
      nil -> send_resp(conn, 404, "")
      {:ok, %{placeholder: nil}} -> send_resp(conn, 404, "")
      {:error, %Ash.Error.Invalid{}} -> send_resp(conn, 404, "")
    end
  end

  # sobelow_skip ["XSS.SendResp"]
  # WebP bytes this app encoded, sent as image/webp with nosniff.
  # no-transform: Bandit would otherwise gzip the already compressed image.
  defp send_picture(conn, webp) do
    conn
    |> put_resp_content_type("image/webp", nil)
    |> put_resp_header("cache-control", "private, max-age=31536000, immutable, no-transform")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, webp)
  end
end
