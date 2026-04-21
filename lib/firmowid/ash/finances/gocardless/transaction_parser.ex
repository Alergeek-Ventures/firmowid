defmodule Firmowid.Ash.Finances.GoCardless.TransactionParser do
  @moduledoc """
  Parses GoCardless API transaction responses into maps suitable for
  `Ash.bulk_create` with the `:upsert_from_sync` action on Transaction.
  """

  require Logger

  defmodule InvalidTransactionAmountError do
    @moduledoc false

    defexception [:message, :transaction_id, :internal_transaction_id, :raw_amount]

    @type t :: %__MODULE__{
            message: String.t(),
            transaction_id: String.t() | nil,
            internal_transaction_id: String.t() | nil,
            raw_amount: term()
          }

    @impl true
    def exception(opts) do
      raw_amount = Keyword.get(opts, :raw_amount)
      transaction_id = Keyword.get(opts, :transaction_id)
      internal_transaction_id = Keyword.get(opts, :internal_transaction_id)

      message =
        "Unsupported GoCardless transaction amount format #{inspect(raw_amount)} " <>
          "for transaction #{inspect(transaction_id || internal_transaction_id)}"

      %__MODULE__{
        message: message,
        transaction_id: transaction_id,
        internal_transaction_id: internal_transaction_id,
        raw_amount: raw_amount
      }
    end
  end

  @valid_amount_pattern ~r/^-?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,3})?$/

  @doc """
  Parses a single GoCardless booked transaction API response into a flat map
  ready for `Ash.bulk_create`.

  Handles:
  - camelCase → snake_case key conversion
  - Nested amount/currency flattening
  - Creditor/debtor account IBAN/BBAN extraction
  - Nest Bank card transaction normalization
  """
  @spec parse(map()) :: {:ok, map()} | {:error, InvalidTransactionAmountError.t()}
  def parse(api_object) do
    data =
      api_object
      |> map_camel_to_snake()
      |> flatten_api_response()
      |> normalize_nest_bank_card_transaction()

    with {:ok, normalized_data} <- normalize_transaction_amount(data) do
      {:ok, extract_fields(normalized_data)}
    end
  end

  @doc """
  Parses a list of GoCardless booked transaction API responses.
  """
  @spec parse_all(list(map())) :: %{transactions: list(map()), errors: list(Exception.t())}
  def parse_all(transactions) do
    transactions
    |> Enum.reduce(%{transactions: [], errors: []}, fn transaction, acc ->
      case parse(transaction) do
        {:ok, parsed_transaction} ->
          %{acc | transactions: [parsed_transaction | acc.transactions]}

        {:error, error} ->
          %{acc | errors: [error | acc.errors]}
      end
    end)
    |> Map.update!(:transactions, &Enum.reverse/1)
    |> Map.update!(:errors, &Enum.reverse/1)
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
      Logger.error("Failed to normalize Nest Bank card transaction: #{Exception.message(error)}")
      data
  end

  defp normalize_transaction_amount(data) do
    amount = Map.get(data, "transaction_amount")

    cond do
      is_nil(amount) ->
        {:error, invalid_transaction_amount_error(data, amount)}

      not is_binary(amount) ->
        {:error, invalid_transaction_amount_error(data, amount)}

      true ->
        normalized_amount = String.trim(amount)

        if Regex.match?(@valid_amount_pattern, normalized_amount) do
          {:ok, Map.put(data, "transaction_amount", String.replace(normalized_amount, ",", ""))}
        else
          {:error, invalid_transaction_amount_error(data, amount)}
        end
    end
  end

  defp invalid_transaction_amount_error(data, raw_amount) do
    InvalidTransactionAmountError.exception(
      raw_amount: raw_amount,
      transaction_id: Map.get(data, "transaction_id"),
      internal_transaction_id: Map.get(data, "internal_transaction_id")
    )
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
