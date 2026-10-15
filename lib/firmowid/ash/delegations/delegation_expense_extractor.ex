defmodule Firmowid.Ash.Delegations.DelegationExpenseExtractor do
  @moduledoc """
  Extracts document number and amount from delegation expense uploads.
  """

  alias Firmowid.Ash.Blobs.Utils.ProcessBlobHelpers

  require Logger

  @system_prompt """
  Extract the document number and gross total amount from this delegation expense document.

  Guidelines:
  - Return the document number exactly as printed. For receipts without a document number, use the receipt number.
  - Return the gross total amount, including VAT/tax.
  - Amount must be a positive number, without a currency symbol.
  """

  @transport_details_schema %{
    type: "object",
    properties: %{
      type: %{type: "string", enum: ["transport"]},
      transport_type: %{type: "string", enum: ["railway", "airplane", "bus", "other"]},
      trips: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            departure_city: %{type: "string"},
            departure_datetime: %{type: "string", format: "date-time"},
            arrival_city: %{type: "string"},
            arrival_datetime: %{type: "string", format: "date-time"}
          }
        }
      }
    }
  }

  @accommodation_details_schema %{
    type: "object",
    properties: %{
      type: %{type: "string", enum: ["accommodation"]},
      locality: %{type: "string"},
      arrival_date: %{type: "string", format: "date"},
      departure_date: %{type: "string", format: "date"},
      description: %{type: "string"}
    }
  }

  @other_details_schema %{
    type: "object",
    properties: %{
      type: %{type: "string", enum: ["other"]},
      description: %{type: "string"}
    }
  }

  @schema %{
    type: "object",
    properties: %{
      document_number: %{type: "string"},
      expense_amount: %{type: "number", exclusiveMinimum: 0}
    },
    required: ["document_number", "expense_amount", "details"]
  }

  @doc """
  Returns extracted details or the reason extraction failed.
  """
  @spec extract(Path.t(), :transport | :accommodation | :other, Date.t(), Date.t()) ::
          {:ok, map()} | {:error, term()}
  def extract(file_path, expense_type, start_date, end_date) do
    extract_details(file_path, expense_type, start_date, end_date)
  end

  defp extract_details(file_path, expense_type, start_date, end_date) do
    schema = put_in(@schema, [:properties, :details], details_schema(expense_type))

    case ProcessBlobHelpers.reducto_client().extract_file(file_path, schema,
           system_prompt: system_prompt(expense_type, start_date, end_date)
         ) do
      {:ok, metadata} ->
        case extracted_details(metadata, expense_type) do
          nil -> extraction_error(:invalid_response)
          details -> {:ok, details}
        end

      {:error, reason} ->
        extraction_error(reason)
    end
  end

  defp details_schema(:transport), do: @transport_details_schema
  defp details_schema(:accommodation), do: @accommodation_details_schema
  defp details_schema(:other), do: @other_details_schema

  defp extraction_error(reason) do
    Logger.error("Delegation expense extraction failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp extracted_details(
         %{"document_number" => document_number, "expense_amount" => amount, "details" => details},
         expense_type
       )
       when is_binary(document_number) and document_number != "" and is_map(details) do
    case decimal(amount) do
      {:ok, amount} ->
        %{
          document_number: document_number,
          expense_amount: Money.new(:PLN, amount),
          details:
            details
            |> Map.put("type", Atom.to_string(expense_type))
            |> Map.put("_union_type", Atom.to_string(expense_type))
        }

      :error ->
        nil
    end
  end

  defp extracted_details(_metadata, _expense_type), do: nil

  defp system_prompt(:transport, start_date, end_date) do
    @system_prompt <>
      """

       Expense category: transport.
       Include details with type "transport", transport_type, and trips. Each trip must include departure_city, departure_datetime, arrival_city, and arrival_datetime.
       The delegation's reported period is #{start_date} to #{end_date}. It is context only.
       Extract every date and time exactly as it appears in the document. Do not adjust dates to fit the delegation period.
      """
  end

  defp system_prompt(:accommodation, start_date, end_date) do
    @system_prompt <>
      """

       Expense category: accommodation.
       Include details with type "accommodation", locality, arrival_date, departure_date, and an optional description.
       The delegation's reported period is #{start_date} to #{end_date}. It is context only.
       Extract every date exactly as it appears in the document. Do not adjust dates to fit the delegation period.
      """
  end

  defp system_prompt(:other, _start_date, _end_date) do
    @system_prompt <>
      """

      Expense category: other.
      Include details with type "other" and description.
      """
  end

  defp decimal(amount) when is_integer(amount) and amount > 0, do: {:ok, Decimal.new(amount)}
  defp decimal(amount) when is_float(amount) and amount > 0, do: {:ok, Decimal.from_float(amount)}

  defp decimal(amount) when is_binary(amount) do
    case Decimal.parse(amount) do
      {decimal, ""} -> positive_decimal(decimal)
      _ -> :error
    end
  end

  defp decimal(_amount), do: :error

  defp positive_decimal(decimal) do
    if Decimal.compare(decimal, Decimal.new(0)) == :gt, do: {:ok, decimal}, else: :error
  end
end
