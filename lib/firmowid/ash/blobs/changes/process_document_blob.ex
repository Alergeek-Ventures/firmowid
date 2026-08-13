defmodule Firmowid.Ash.Blobs.Changes.ProcessDocumentBlob do
  @moduledoc false
  use Ash.Resource.Change

  alias Ash.Error.Invalid
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query
  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, blob ->
      actor = %SystemActor{
        org_id: blob.organization_id,
        role: :document_blob_processor,
        blob_id: blob.id
      }

      scope = %Scope{actor: actor, tenant: blob.organization_id}
      opts = [scope: scope]

      case run_processing(blob, opts) do
        :ok ->
          {:ok, blob}

        {:error, reason} ->
          Logger.error("Failed to process document blob #{blob.id}: #{inspect(reason)}")
          report_failure(reason, blob)
          _ = handle_failure(blob, reason, opts)
          {:ok, blob}
      end
    end)
  end

  defp run_processing(blob, opts) do
    with {:ok, blob} <- ensure_processing(blob, opts),
         {:ok, blob_url} <- load_blob_url(blob, opts),
         :ok <- process_document_blob(blob.processing_target, blob_url, blob, opts),
         {:ok, _updated_blob} <- mark_succeeded(blob, opts) do
      :ok
    end
  rescue
    error ->
      {:error, error}
  end

  # Register new processing targets in process_document_blob and get_error_message functions

  defp process_document_blob(:cost_invoice, blob_url, blob, opts),
    do: Firmowid.Ash.Blobs.Utils.ProcessCostInvoiceBlob.run_processing(blob_url, blob, opts)

  defp process_document_blob(:employment_contract, blob_url, blob, opts),
    do: Firmowid.Ash.Blobs.Utils.ProcessEmploymentContractBlob.run_processing(blob_url, blob, opts)

  defp process_document_blob(_, _blob_url, _blob, _opts), do: {:error, :unsupported_processing_target}

  defp get_error_message(:invalid_document, :cost_invoice),
    do: "Plik nie zawiera danych wymaganych dla faktury kosztowej."

  defp get_error_message(:invalid_document, :employment_contract),
    do: "Plik nie zawiera danych wymaganych dla umowy o pracę."

  defp get_error_message(_reason, _target),
    do: "Wystąpił problem po naszej stronie podczas przetwarzania pliku. Został zgłoszony - spróbuj ponownie później."

  defp ensure_processing(blob, opts) do
    blob
    |> Ash.Changeset.for_update(:mark_processing, %{}, opts)
    |> Ash.update(opts)
  end

  defp load_blob_url(blob, opts) do
    loaded = Ash.load!(blob, [:url], opts)
    {:ok, loaded.url}
  end

  defp mark_succeeded(blob, opts) do
    blob
    |> Ash.Changeset.for_update(:mark_processing_succeeded, %{}, opts)
    |> Ash.update(opts)
  end

  defp handle_failure(blob, reason, opts) do
    failure = %{
      error: normalize_error(reason),
      error_code: normalize_error_code(reason),
      error_message: get_error_message(reason, blob.processing_target)
    }

    case Blob
         |> Ash.Query.filter(id == ^blob.id)
         |> Ash.read_one(opts) do
      {:ok, nil} ->
        Logger.warning("Blob #{blob.id} not found when trying to mark processing as failed")
        {:ok, nil}

      {:ok, blob_record} ->
        blob_record
        |> Ash.Changeset.for_update(:mark_processing_failed, failure, opts)
        |> Ash.update(opts)

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_error(:invalid_document), do: ":invalid_document"
  defp normalize_error(%Invalid{} = error), do: Exception.message(error)
  defp normalize_error(reason), do: inspect(reason)

  defp normalize_error_code(:invalid_document), do: "invalid_document"
  defp normalize_error_code(_reason), do: "processing_failed"

  defp report_failure(:invalid_document, _blob), do: :ok

  defp report_failure(reason, blob) do
    Sentry.capture_exception(RuntimeError.exception("Document blob processing failed"),
      tags: %{
        processing_target: blob.processing_target,
        source: "document_blob_processing"
      },
      extra: %{
        blob_id: blob.id,
        error: inspect(reason),
        organization_id: blob.organization_id,
        original_filename: blob.original_filename
      }
    )
  rescue
    sentry_error ->
      Logger.warning("Failed to report document blob processing error to Sentry: #{Exception.message(sentry_error)}")
  end
end
