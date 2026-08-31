defmodule Firmowid.Ash.Delegations.DelegationExpenseExtractor do
  @moduledoc """
  Extracts document number and amount from delegation expense uploads.
  """

  alias Firmowid.Ash.Blobs.Utils.ProcessBlobHelpers

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

  @fallbacks %{
    transport: %{document_number: "TRANSPORT-001", expense_amount: "36.20"},
    accommodation: %{document_number: "NOCLEG-001", expense_amount: "530.20"},
    other: %{document_number: "INNE-001", expense_amount: "78.00"}
  }

  @doc """
  Returns extracted details, or type-specific samples when extraction is unavailable.
  """
  @spec extract(Path.t(), :transport | :accommodation | :other) :: %{
          document_number: String.t(),
          expense_amount: Money.t()
        }
  def extract(file_path, expense_type) do
    if Application.get_env(:firmowid, :delegation_expense_extraction_enabled, true) do
      extract_details(file_path, expense_type)
    else
      fallback(expense_type)
    end
  end

  defp extract_details(file_path, expense_type) do
    case ProcessBlobHelpers.reducto_client().extract_file(file_path, @schema, system_prompt: @system_prompt) do
      {:ok, metadata} ->
        details(metadata) || fallback(expense_type)

      {:error, _reason} ->
        fallback(expense_type)
    end
  rescue
    _error -> fallback(expense_type)
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

  defp fallback(expense_type) do
    %{document_number: document_number, expense_amount: amount} =
      Map.fetch!(@fallbacks, expense_type)

    %{document_number: document_number, expense_amount: Money.new(:PLN, Decimal.new(amount))}
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
