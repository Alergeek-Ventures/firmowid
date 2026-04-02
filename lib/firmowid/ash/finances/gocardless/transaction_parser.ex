defmodule Firmowid.Ash.Finances.GoCardless.TransactionParser do
  @moduledoc """
  Parses GoCardless API transaction responses into maps suitable for
  `Ash.bulk_create` with the `:upsert_from_sync` action on Transaction.
  """

  @doc """
  Parses a single GoCardless booked transaction API response into a flat map
  ready for `Ash.bulk_create`.

  Handles:
  - camelCase → snake_case key conversion
  - Nested amount/currency flattening
  - Creditor/debtor account IBAN/BBAN extraction
  - Nest Bank card transaction normalization
  """
  @spec parse(map()) :: map()
  def parse(api_object) do
    api_object
    |> map_camel_to_snake()
    |> flatten_api_response()
    |> normalize_nest_bank_card_transaction()
    |> extract_fields()
  end

  @doc """
  Parses a list of GoCardless booked transaction API responses.
  """
  @spec parse_all(list(map())) :: list(map())
  def parse_all(transactions) do
    Enum.map(transactions, &parse/1)
  end

  defp map_camel_to_snake(api_object) do
    Recase.Enumerable.convert_keys(api_object, &Recase.to_snake/1)
  end

  defp flatten_api_response(data) do
    data
    |> Map.put("transaction_currency", get_in(data, ["transaction_amount", "currency"]))
    |> Map.update("creditor_account", "N/A", &extract_iban_or_bban/1)
    |> Map.update("debtor_account", "N/A", &extract_iban_or_bban/1)
    |> Map.update("transaction_amount", nil, fn
      %{"amount" => amount} -> amount
      other -> other
    end)
  end

  defp extract_iban_or_bban(nil), do: "N/A"
  defp extract_iban_or_bban(%{"iban" => iban}), do: iban
  defp extract_iban_or_bban(%{"bban" => bban}), do: bban
  defp extract_iban_or_bban(_), do: "N/A"

  defp normalize_nest_bank_card_transaction(data) do
    creditor_name = Map.get(data, "creditor_name", "")
    remittance = Map.get(data, "remittance_information_unstructured", "")

    if creditor_name == "Nest Bank S.A." and String.contains?(remittance, "Nr karty") do
      [new_creditor_name | [description | _]] = String.split(remittance, "Nr karty")

      new_creditor_name =
        new_creditor_name
        |> String.trim()
        |> String.replace_trailing(",", "")

      description = String.trim("Nr karty " <> description)

      data
      |> Map.put("creditor_name", new_creditor_name)
      |> Map.put("remittance_information_unstructured", description)
    else
      data
    end
  rescue
    error ->
      ErrorTracker.report(error, __STACKTRACE__)
      data
  end

  @fields ~w(
    transaction_id internal_transaction_id debtor_name debtor_account
    creditor_name creditor_account transaction_amount transaction_currency
    booking_date value_date remittance_information_unstructured
  )

  defp extract_fields(data) do
    data
    |> Map.take(@fields)
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Map.update(:debtor_name, "N/A", &(&1 || "N/A"))
    |> Map.update(:debtor_account, "N/A", &(&1 || "N/A"))
    |> Map.update(:creditor_name, "N/A", &(&1 || "N/A"))
    |> Map.update(:creditor_account, "N/A", &(&1 || "N/A"))
  end
end
