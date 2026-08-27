defmodule Firmowid.Ash.Blobs.Utils.ProcessEmploymentContractBlob do
  @moduledoc """
  Processes a pending blob into an employment contract by extracting metadata.
  """

  alias Firmowid.Ash.Blobs.Utils.ProcessBlobHelpers
  alias Firmowid.Ash.Payroll

  @employment_contract_system_prompt """
  Extract data from this employment contract.

  Guidelines:
  - Dates should be in YYYY-MM-DD format
  - Currency should be a 3-letter ISO 4217 code (e.g., PLN, USD, EUR)
  - If the document is not an employment contract set document_type to "invalid"
  - If the document is an employment contract but NOT yet signed (or have only one signature), set document_type to "employment_contract"
  - If the document is an employment contract that has been signed by all parties (contains both employee and employer signatures), set document_type to "signed_employment_contract"
  - Make sure that salary is in hourly rate if it is not then convert it to hourly rate based on the information in the document (if you cannot determine the hourly rate, return null)
    (e.g., if it's monthly salary, and it's full time contract then divide the salary by 160 hours)
  - contract_type should be one of: "uop" (umowa o pracę), "b2b", "uz" (umowa zlecenie), "uod" (umowa o dzieło)
    If you cannot determine the contract type, return null
  - position should be the job title or role (e.g. "Software Developer", "Accountant")
    If you cannot determine the position, return null
  - signed_at should be the date the contract was signed
    If you cannot determine the signed date, return null
  """

  @employment_contract_schema %{
    type: "object",
    properties: %{
      document_type: %{
        type: "string",
        enum: ["employment_contract", "signed_employment_contract", "invalid"]
      },
      starts_at: %{type: "string", format: "date"},
      salary_amount: %{type: "number"},
      salary_currency: %{type: "string"},
      contract_type: %{type: ["string", "null"], enum: ["uop", "b2b", "uz", "uod", nil]},
      position: %{type: ["string", "null"]},
      signed_at: %{type: ["string", "null"], format: "date"}
    },
    required: ["document_type"],
    if: %{
      properties: %{document_type: %{enum: ["employment_contract", "signed_employment_contract"]}},
      required: ["document_type"]
    },
    then: %{
      required: [
        "starts_at",
        "salary_amount",
        "salary_currency"
      ]
    }
  }

  def run_processing(blob_url, blob, opts) do
    with {:ok, extracted_metadata} <- extract_metadata(blob_url),
         :ok <- ensure_employment_contract_document(extracted_metadata) do
      create_employment_contract(extracted_metadata, blob, opts)
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

  defp ensure_employment_contract_document(%{"document_type" => type})
       when type in ["employment_contract", "signed_employment_contract"], do: :ok

  defp ensure_employment_contract_document(_), do: {:error, :invalid_document}

  defp create_employment_contract(extracted_metadata, blob, opts) do
    with :ok <- validate_salary_metadata(extracted_metadata) do
      status = determine_status(extracted_metadata)

      signed_at =
        case extracted_metadata["document_type"] do
          "signed_employment_contract" -> parse_date(extracted_metadata["signed_at"])
          "employment_contract" -> parse_date(extracted_metadata["signed_at"])
          _ -> nil
        end

      attrs =
        extracted_metadata
        |> Map.delete("document_type")
        |> Map.delete("salary_currency")
        |> Map.delete("salary_amount")
        |> Map.update("contract_type", nil, &parse_contract_type/1)
        |> Map.put("signed_at", signed_at)
        |> Map.put("status", status)
        |> Map.put(
          "salary",
          Money.new!(
            extracted_metadata["salary_currency"],
            Decimal.new(to_string(extracted_metadata["salary_amount"]))
          )
        )
        |> Map.put("blob_id", blob.id)
        |> Map.put("user_id", blob.processing_metadata["user_id"])

      case Payroll.create_employment_contract(attrs, opts) do
        {:ok, _contract} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp validate_salary_metadata(%{"salary_amount" => amount, "salary_currency" => currency})
       when is_binary(amount) and amount != "" and is_binary(currency) and currency != "" do
    :ok
  end

  defp validate_salary_metadata(%{"salary_amount" => amount}) when is_number(amount) and not is_nil(amount) do
    :ok
  end

  defp validate_salary_metadata(_), do: {:error, :missing_salary_metadata}

  defp determine_status(%{"document_type" => "signed_employment_contract"}), do: :signed

  defp determine_status(_), do: :pending_signature

  defp parse_contract_type(nil), do: nil
  defp parse_contract_type(type) when is_atom(type), do: type
  defp parse_contract_type(type) when is_binary(type), do: String.to_existing_atom(type)

  defp parse_date(nil), do: Date.utc_today()
  defp parse_date(date_string) when is_binary(date_string), do: Date.from_iso8601!(date_string)
  defp parse_date(%Date{} = date), do: date
end
