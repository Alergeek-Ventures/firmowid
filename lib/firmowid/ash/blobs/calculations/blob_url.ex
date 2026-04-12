defmodule Firmowid.Ash.Blobs.Calculations.BlobUrl do
  @moduledoc """
  Generates a presigned S3 URL from the blob's stored path.

  Callers must explicitly load this calculation when they need the URL:

      blob |> Ash.load!(:url)
      Ash.Query.load(query, :url)

  Presigned URLs expire after 200 seconds (matching the legacy behaviour).
  """
  use Ash.Resource.Calculation

  alias Firmowid.S3Client

  @presigned_url_ttl 200

  @impl true
  def load(_query, _opts, _context) do
    [:blob_path]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      if record.blob_path do
        {:ok, url} = S3Client.presigned_get_url(record.blob_path, expires_in: @presigned_url_ttl)

        url
      end
    end)
  end
end
