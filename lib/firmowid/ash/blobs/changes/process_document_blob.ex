defmodule Firmowid.Ash.Blobs.Changes.ProcessDocumentBlob do
  @moduledoc false
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query

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

        {:error, :invalid_document} ->
          case handle_invalid_document(blob, opts) do
            {:ok, _updated_blob} -> {:ok, blob}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
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
  end

  # Register new processing targets in process_document_blob and invalid_document_error_message functions

  defp process_document_blob(:cost_invoice, blob_url, blob, opts),
    do: Firmowid.Ash.Blobs.Utils.ProcessCostInvoiceBlob.run_processing(blob_url, blob, opts)

  defp process_document_blob(:employment_contract, blob_url, blob, opts),
    do: Firmowid.Ash.Blobs.Utils.ProcessEmploymentContractBlob.run_processing(blob_url, blob, opts)

  defp process_document_blob(_, _blob_url, _blob, _opts), do: {:error, :unsupported_processing_target}

  defp invalid_document_error_message(:cost_invoice), do: "Plik nie zawiera danych wymaganych dla faktury kosztowej."

  defp invalid_document_error_message(:employment_contract), do: "Plik nie zawiera danych wymaganych dla umowy o pracę."

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

  defp handle_invalid_document(blob, opts) do
    failure = %{
      error: ":invalid_document",
      error_code: "invalid_document",
      error_message: invalid_document_error_message(blob.processing_target)
    }

    case Blob
         |> Ash.Query.filter(id == ^blob.id)
         |> Ash.read_one(opts) do
      {:ok, nil} ->
        {:error, :blob_not_found}

      {:ok, blob_record} ->
        blob_record
        |> Ash.Changeset.for_update(:mark_processing_failed, failure, opts)
        |> Ash.update(opts)

      {:error, error} ->
        {:error, error}
    end
  end
end
