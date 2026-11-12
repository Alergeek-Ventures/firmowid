defmodule Firmowid.Blobs.Changes.ProcessDocumentBlob do
  @moduledoc false
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Blobs.Blob
  alias Firmowid.Scope
  alias Firmowid.SystemActor

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

        {:error, reason} ->
          with {:ok, _failed_blob} <- update_failed_blob(blob, failure(reason, blob), opts) do
            {:ok, blob}
          end
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
    do: Firmowid.Blobs.Utils.ProcessCostInvoiceBlob.run_processing(blob_url, blob, opts)

  defp process_document_blob(:employment_contract, blob_url, blob, opts),
    do: Firmowid.Blobs.Utils.ProcessEmploymentContractBlob.run_processing(blob_url, blob, opts)

  defp process_document_blob(_, _blob_url, _blob, _opts), do: {:error, :unsupported_processing_target}

  # Failures are stored as English msgids and translated where they are shown,
  # in the language of the person looking at them.
  defp invalid_document_error_message(:cost_invoice),
    do: gettext_noop("The file does not contain the data required for a cost invoice.")

  defp invalid_document_error_message(:employment_contract),
    do: gettext_noop("Upload a contract, an employee declaration or a payroll document.")

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

  defp failure(:invalid_document, blob) do
    %{
      error: ":invalid_document",
      error_code: "invalid_document",
      error_message: invalid_document_error_message(blob.processing_target)
    }
  end

  defp failure({:duplicate_ksef_invoice, cost_invoice_id}, _blob) do
    %{
      error: ":duplicate_ksef_invoice",
      error_code: "duplicate_ksef_invoice",
      error_message: gettext_noop("This KSeF invoice is already in the system."),
      cost_invoice_id: cost_invoice_id
    }
  end

  defp failure(:missing_salary_metadata, _blob) do
    %{
      error: ":missing_salary_metadata",
      error_code: "missing_salary_metadata",
      error_message: gettext_noop("Could not extract the salary data from the contract.")
    }
  end

  defp failure(reason, _blob) do
    %{
      error: inspect(reason),
      error_code: "processing_failed",
      error_message: gettext_noop("Could not process the file.")
    }
  end

  defp update_failed_blob(blob, failure, opts) do
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
