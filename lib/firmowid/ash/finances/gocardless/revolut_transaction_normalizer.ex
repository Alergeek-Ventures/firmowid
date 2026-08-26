defmodule Firmowid.Ash.Finances.GoCardless.RevolutTransactionNormalizer do
  @moduledoc """
  Applies bounded, Revolut-specific normalization to a canonical GoCardless
  transaction map.

  The normalizer runs after amount and description normalization and does not
  add provider-specific data to the persisted transaction schema.
  """

  alias Firmowid.Ash.Finances.TransactionDirection

  @doc """
  Normalizes provider transaction details for a Revolut bank account.

  The transaction map uses the parser's internal snake-case string keys.
  """
  @spec normalize(map(), map()) :: map()
  def normalize(data, bank_account) do
    code = data |> Map.get("proprietary_bank_transaction_code", "") |> code()
    institution_name = bank_institution_label(bank_account)

    case code do
      "EXCHANGE" -> normalize_exchange(data, bank_account, institution_name)
      "CHARGE" -> normalize_charge(data, bank_account, institution_name)
      "TOPUP" -> put_description_if_missing(data, "Doładowanie Revolut")
      "CARD_PAYMENT" -> put_description_if_missing(data, "Płatność kartą")
      "CASH_WITHDRAWAL" -> put_description_if_missing(data, "Wypłata gotówki")
      "TRANSFER" -> put_description_if_missing(data, "Przelew")
      _ -> data
    end
  end

  defp normalize_exchange(data, bank_account, institution_name) do
    data
    |> put_directional_name(bank_account, institution_name)
    |> put_description_if_missing("Wymiana walut")
    |> append_exchange_summary()
  end

  defp normalize_charge(data, bank_account, institution_name) do
    data
    |> put_directional_name(bank_account, institution_name)
    |> put_description_if_missing("Opłata Revolut")
  end

  defp put_directional_name(data, bank_account, institution_name) do
    direction = transaction_direction(data, bank_account)

    case direction do
      :income -> put_name_if_missing(data, "debtor_name", institution_name)
      :expense -> put_name_if_missing(data, "creditor_name", institution_name)
    end
  end

  defp transaction_direction(data, bank_account) do
    transaction = %{
      amount: Map.get(data, "amount"),
      creditor_account: Map.get(data, "creditor_account"),
      debtor_account: Map.get(data, "debtor_account"),
      bank_account: bank_account
    }

    TransactionDirection.direction(transaction, account_value(bank_account, :iban))
  end

  defp put_name_if_missing(data, key, name) do
    if missing_party_name?(Map.get(data, key)), do: Map.put(data, key, name), else: data
  end

  defp put_description_if_missing(data, fallback) do
    if missing?(Map.get(data, "remittance_information_unstructured")),
      do: Map.put(data, "remittance_information_unstructured", fallback),
      else: data
  end

  defp append_exchange_summary(data) do
    with %{} = exchange <- first_exchange(Map.get(data, "currency_exchange")),
         source when is_binary(source) <-
           currency_component(nested_value(exchange, "source_currency")),
         target when is_binary(target) <-
           currency_component(nested_value(exchange, "target_currency")),
         rate when is_binary(rate) <- component(nested_value(exchange, "exchange_rate")) do
      suffix = "#{source} → #{target} · kurs #{rate}"
      description = Map.get(data, "remittance_information_unstructured")

      if is_binary(description) and String.contains?(description, suffix),
        do: data,
        else: Map.put(data, "remittance_information_unstructured", "#{description} · #{suffix}")
    else
      _ -> data
    end
  end

  defp first_exchange(%{} = exchange), do: exchange
  defp first_exchange(values) when is_list(values), do: Enum.find(values, &is_map/1)
  defp first_exchange(_), do: nil

  defp nested_value(map, "source_currency"), do: Map.get(map, "source_currency") || Map.get(map, :source_currency)

  defp nested_value(map, "target_currency"), do: Map.get(map, "target_currency") || Map.get(map, :target_currency)

  defp nested_value(map, "exchange_rate"), do: Map.get(map, "exchange_rate") || Map.get(map, :exchange_rate)

  defp component(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp component(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp component(_), do: nil

  defp currency_component(value) do
    case component(value) do
      nil -> nil
      value -> String.upcase(value)
    end
  end

  defp code(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp code(_), do: ""

  defp account_value(account, key) do
    Map.get(account, key) || Map.get(account, Atom.to_string(key))
  end

  defp bank_institution_label(account) do
    case account_value(account, :institution_name) do
      value when is_binary(value) ->
        if String.trim(value) == "" or String.upcase(String.trim(value)) == "N/A",
          do: "Revolut",
          else: value

      _ ->
        "Revolut"
    end
  end

  defp useful?(value), do: is_binary(value) and String.trim(value) not in ["", "N/A"]

  defp missing?(nil), do: true
  defp missing?(value), do: not useful?(value)

  defp missing_party_name?(nil), do: true
  defp missing_party_name?(value), do: is_binary(value) and String.trim(value) == ""
end
