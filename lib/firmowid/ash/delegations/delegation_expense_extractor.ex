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

  @schema %{
    type: "object",
    properties: %{
      document_number: %{type: "string"},
      expense_amount: %{type: "number", exclusiveMinimum: 0}
    },
    required: ["document_number", "expense_amount"]
  }

  @doc """
  Returns extracted details or the reason extraction failed.
  """
  @spec extract(Path.t(), :transport | :accommodation | :other) :: {:ok, map()} | {:error, term()}
  def extract(file_path, _expense_type) do
    extract_details(file_path)
  end

  defp extract_details(file_path) do
    case ProcessBlobHelpers.reducto_client().extract_file(file_path, @schema, system_prompt: @system_prompt) do
      {:ok, metadata} ->
        case details(metadata) do
          nil -> extraction_error(:invalid_response)
          details -> {:ok, details}
        end

      {:error, reason} ->
        extraction_error(reason)
    end
  end

  defp extraction_error(reason) do
    Logger.error("Delegation expense extraction failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp details(%{"document_number" => document_number, "expense_amount" => amount})
       when is_binary(document_number) and document_number != "" do
    case decimal(amount) do
      {:ok, amount} ->
        %{document_number: document_number, expense_amount: Money.new(:PLN, amount)}

      :error ->
        nil
    end
  end

  defp details(_metadata), do: nil

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
