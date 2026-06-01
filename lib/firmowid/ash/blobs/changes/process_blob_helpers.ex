defmodule Firmowid.Ash.Blobs.Changes.ProcessBlobHelpers do
  @moduledoc """
  Shared helper functions for blob processing changes.

  Extracted to eliminate code duplication between `ProcessCostInvoiceBlob`
  and `ProcessEmploymentContractBlob`.
  """

  alias Ash.Error.Invalid
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Invoicing.Services.ReductoApiClient

  require Ash.Query

  @doc """
  Marks a blob as currently being processed.
  """
  def ensure_processing(blob, opts) do
    blob
    |> Ash.Changeset.for_update(:mark_processing, %{}, opts)
    |> Ash.update(opts)
  end

  @doc """
  Loads the presigned URL for a blob.
  """
  def load_blob_url(blob, opts) do
    loaded = Ash.load!(blob, [:url], opts)
    {:ok, loaded.url}
  end

  @doc """
  Marks a blob as successfully processed.
  """
  def mark_succeeded(blob, opts) do
    blob
    |> Ash.Changeset.for_update(:mark_processing_succeeded, %{}, opts)
    |> Ash.update(opts)
  end

  @doc """
  Returns the configured Reducto API client module.
  """
  def reducto_client do
    Application.get_env(:firmowid, :reducto_api_client_module, ReductoApiClient)
  end

  @doc """
  Handles a processing failure by updating the blob with error details.
  """
  def handle_failure(blob, reason, opts, error_message) do
    failure = %{
      error: normalize_error(reason),
      error_code: normalize_error_code(reason),
      error_message: error_message
    }

    Blob
    |> Ash.Query.filter(id == ^blob.id)
    |> Ash.read_one!(opts)
    |> Ash.Changeset.for_update(:mark_processing_failed, failure, opts)
    |> Ash.update(opts)
  end

  defp normalize_error(:invalid_document), do: ":invalid_document"
  defp normalize_error(%Invalid{} = error), do: Exception.message(error)
  defp normalize_error(reason), do: inspect(reason)

  defp normalize_error_code(:invalid_document), do: "invalid_document"
  defp normalize_error_code(%Invalid{}), do: "invalid_document"
  defp normalize_error_code(_reason), do: "processing_failed"
end
