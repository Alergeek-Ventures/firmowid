defmodule Firmowid.Ash.Blobs.Changes.ProcessEmploymentContractBlob do
  @moduledoc """
  Processes a pending blob into an employment contract by extracting metadata.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs.Changes.ProcessBlobHelpers
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @employment_contract_system_prompt """
  Extract data from this employment contract.

  Guidelines:
  - Dates should be in YYYY-MM-DD format
  - Currency should be a 3-letter ISO 4217 code (e.g., PLN, USD, EUR)
  - If the document is not an employment contract set document_type to "invalid"
  - Make sure that salary is in hourly rate if it is not then convert it to hourly rate based on the information in the document
    (e.g., if it's monthly salary, and it's full time contract then divide the salary by 160 hours)
  """

  @employment_contract_schema %{
    type: "object",
    properties: %{
      document_type: %{type: "string", enum: ["employment_contract", "invalid"]},
      starts_at: %{type: "string", format: "date"},
      worker_full_name: %{type: "string"},
      salary_amount: %{type: "number"},
      salary_currency: %{type: "string"}
    },
    required: ["document_type"],
    if: %{
      properties: %{document_type: %{const: "employment_contract"}},
      required: ["document_type"]
    },
    then: %{
      required: [
        "starts_at",
        "worker_full_name",
        "salary_amount",
        "salary_currency"
      ]
    }
  }

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, blob ->
      actor = %SystemActor{
        org_id: blob.organization_id,
        role: :employment_contract_processor,
        blob_id: blob.id
      }

      scope = %Scope{actor: actor, tenant: blob.organization_id}
      opts = [actor: actor, tenant: blob.organization_id, scope: scope]

      case run_processing(blob, opts) do
        :ok ->
          {:ok, blob}

        {:error, reason} ->
          Logger.warning("Failed to process employment contract blob #{blob.id}: #{inspect(reason)}")

          _ = handle_failure(blob, reason, opts)
          {:ok, blob}
      end
    end)
  end

  defp run_processing(blob, opts) do
    with {:ok, blob} <- ProcessBlobHelpers.ensure_processing(blob, opts),
         {:ok, blob_url} <- ProcessBlobHelpers.load_blob_url(blob, opts),
         {:ok, extracted_metadata} <- extract_metadata(blob_url),
         :ok <- ensure_employment_contract_document(extracted_metadata),
         :ok <- create_employment_contract(extracted_metadata, blob, opts),
         {:ok, _updated_blob} <- ProcessBlobHelpers.mark_succeeded(blob, opts) do
      :ok
    end
  rescue
    error ->
      {:error, error}
  end

  defp extract_metadata(blob_url) do
    ProcessBlobHelpers.reducto_client().extract(blob_url, @employment_contract_schema,
      system_prompt: @employment_contract_system_prompt
    )
  end

  defp ensure_employment_contract_document(%{"document_type" => "employment_contract"}), do: :ok
  defp ensure_employment_contract_document(_), do: {:error, :invalid_document}

  defp create_employment_contract(extracted_metadata, blob, opts) do
    attrs =
      extracted_metadata
      |> Map.delete("document_type")
      |> Map.delete("salary_currency")
      |> Map.delete("salary_amount")
      |> Map.put(
        "salary",
        Money.new!(extracted_metadata["salary_currency"], extracted_metadata["salary_amount"])
      )
      |> Map.put("blob_id", blob.id)
      |> Map.put("user_id", blob.processing_metadata["user_id"])

    case Payroll.create_employment_contract(attrs, opts) do
      {:ok, _contract} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_failure(blob, reason, opts) do
    ProcessBlobHelpers.handle_failure(
      blob,
      reason,
      opts,
      "Plik nie zawiera danych wymaganych dla umowy."
    )
  end
end
