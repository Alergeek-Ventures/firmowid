defmodule Firmowid.Ash.Finances.GoCardless.TransactionParser do
  @moduledoc """
  Parses GoCardless API transaction responses into maps suitable for
  `Ash.bulk_create` with the `:upsert_from_sync` action on Transaction.
  """

  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Finances.GoCardless.RevolutTransactionNormalizer

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

  defmodule InvalidTransactionCurrencyError do
    @moduledoc false

    defexception [:message, :transaction_id, :internal_transaction_id, :raw_currency]

    @type t :: %__MODULE__{
            message: String.t(),
            transaction_id: String.t() | nil,
            internal_transaction_id: String.t() | nil,
            raw_currency: term()
          }

    @impl true
    def exception(opts) do
      raw_currency = Keyword.get(opts, :raw_currency)
      transaction_id = Keyword.get(opts, :transaction_id)
      internal_transaction_id = Keyword.get(opts, :internal_transaction_id)

      message =
        "Unsupported GoCardless transaction currency format #{inspect(raw_currency)} " <>
          "for transaction #{inspect(transaction_id || internal_transaction_id)}"

      %__MODULE__{
        message: message,
        transaction_id: transaction_id,
        internal_transaction_id: internal_transaction_id,
        raw_currency: raw_currency
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
  - Description variant normalization, preserving provider precedence
  - Completion of the omitted account-owned party from bank-account details
  - Nest Bank card transaction normalization
  """
  @spec parse(map()) :: {:ok, map()} | {:error, InvalidTransactionAmountError.t()}
  def parse(api_object), do: parse(api_object, nil)

  @doc """
  Parses a transaction and optionally uses the bank account to complete the
  account-owned side when GoCardless omitted it.
  """
  @spec parse(map(), map() | nil) :: {:ok, map()} | {:error, InvalidTransactionAmountError.t()}
  def parse(api_object, bank_account) do
    data =
      api_object
      |> map_camel_to_snake()
      |> flatten_api_response()
      |> normalize_nest_bank_card_transaction()
      |> put_description()

    with {:ok, normalized_data} <- normalize_transaction_amount(data),
         {:ok, money_data} <- normalize_money(normalized_data) do
      {:ok,
       money_data
       |> normalize_revolut_transaction(bank_account)
       |> extract_fields()
       |> complete_own_account_details(bank_account)}
    end
  end

  @doc """
  Parses a list of GoCardless booked transaction API responses.
  """
  @spec parse_all(list(map())) :: %{transactions: list(map()), errors: list(Exception.t())}
  def parse_all(transactions), do: parse_all(transactions, nil)

  @doc """
  Parses a list of transactions, optionally supplying bank-account context for
  completing omitted account-owned party details.
  """
  @spec parse_all(list(map()), map() | nil) :: %{
          transactions: list(map()),
          errors: list(Exception.t())
        }
  def parse_all(transactions, bank_account) do
    transactions
    |> Enum.reduce(%{transactions: [], errors: []}, fn transaction, acc ->
      case parse(transaction, bank_account) do
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

  defp normalize_revolut_transaction(data, bank_account) do
    if revolut_account?(bank_account),
      do: RevolutTransactionNormalizer.normalize(data, bank_account),
      else: data
  end

  defp revolut_account?(account) when is_map(account) do
    institution_id = Map.get(account, :institution_id) || Map.get(account, "institution_id")

    is_binary(institution_id) and
      institution_id |> String.trim() |> String.upcase() |> String.starts_with?("REVOLUT_")
  end

  defp revolut_account?(_), do: false

  defp flatten_api_response(data) do
    data
    |> Map.put("currency", get_in(data, ["transaction_amount", "currency"]))
    |> Map.put("amount", get_in(data, ["transaction_amount", "amount"]))
    |> Map.update("creditor_account", nil, &extract_iban_or_bban/1)
    |> Map.update("debtor_account", nil, &extract_iban_or_bban/1)
  end

  defp extract_iban_or_bban(nil), do: nil
  defp extract_iban_or_bban(%{"iban" => iban}), do: iban
  defp extract_iban_or_bban(%{"bban" => bban}), do: bban
  defp extract_iban_or_bban(_), do: nil

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

  defp put_description(data) do
    description =
      Enum.find_value(
        [
          "remittance_information_unstructured",
          "remittance_information_unstructured_array",
          "remittance_information_structured",
          "remittance_information_structured_array",
          "additional_information",
          "additional_information_structured"
        ],
        &normalize_description(Map.get(data, &1))
      )

    if useful_value?(description),
      do: Map.put(data, "remittance_information_unstructured", description),
      else: data
  end

  defp normalize_description(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_description(values) when is_list(values) do
    values
    |> Enum.map(&normalize_description/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
    |> normalize_description()
  end

  defp normalize_description(%{"reference" => reference}), do: normalize_description(reference)
  defp normalize_description(%{reference: reference}), do: normalize_description(reference)
  defp normalize_description(_), do: nil

  defp useful_value?(value), do: not is_nil(normalize_description(value))

  defp complete_own_account_details(parsed, nil), do: parsed

  defp complete_own_account_details(parsed, bank_account) do
    owner_name = Map.get(bank_account, :owner_name) || Map.get(bank_account, "owner_name")
    iban = Map.get(bank_account, :iban) || Map.get(bank_account, "iban")

    own_side =
      cond do
        Money.positive?(parsed.amount) -> :creditor
        Money.negative?(parsed.amount) -> :debtor
        true -> nil
      end

    case own_side do
      nil ->
        parsed

      side ->
        if opposite_side_matches_account?(parsed, side, iban),
          do: parsed,
          else: complete_own_side(parsed, side, owner_name, iban)
    end
  end

  defp opposite_side_matches_account?(parsed, :creditor, iban),
    do: matching_account?(Map.get(parsed, :debtor_account), iban)

  defp opposite_side_matches_account?(parsed, :debtor, iban),
    do: matching_account?(Map.get(parsed, :creditor_account), iban)

  defp complete_own_side(parsed, :creditor, owner_name, iban) do
    complete_own_side(parsed, :creditor_name, :creditor_account, owner_name, iban)
  end

  defp complete_own_side(parsed, :debtor, owner_name, iban) do
    complete_own_side(parsed, :debtor_name, :debtor_account, owner_name, iban)
  end

  defp complete_own_side(parsed, name_key, account_key, owner_name, iban) do
    provider_name = Map.get(parsed, name_key)
    provider_account = Map.get(parsed, account_key)

    if missing_value?(provider_name) and missing_value?(provider_account) and
         useful_account_value?(owner_name) and useful_account_value?(iban) do
      parsed
      |> Map.put(name_key, owner_name)
      |> Map.put(account_key, iban)
    else
      parsed
    end
  end

  defp missing_value?(nil), do: true
  defp missing_value?("N/A"), do: true

  defp missing_value?(value) when is_binary(value) do
    String.trim(value) in ["", "N/A"]
  end

  defp missing_value?(_), do: false

  defp useful_account_value?(value), do: useful_value?(value) and not missing_value?(value)

  defp matching_account?(provider_account, owner_iban) do
    useful_account_value?(provider_account) and
      useful_account_value?(owner_iban) and
      BankAccount.normalize_iban(provider_account) == BankAccount.normalize_iban(owner_iban)
  end

  defp normalize_transaction_amount(data) do
    amount = Map.get(data, "amount")

    cond do
      is_nil(amount) ->
        {:error, invalid_transaction_amount_error(data, amount)}

      not is_binary(amount) ->
        {:error, invalid_transaction_amount_error(data, amount)}

      true ->
        normalized_amount = String.trim(amount)

        if Regex.match?(@valid_amount_pattern, normalized_amount) do
          {:ok, Map.put(data, "amount", Decimal.new(String.replace(normalized_amount, ",", "")))}
        else
          {:error, invalid_transaction_amount_error(data, amount)}
        end
    end
  end

  defp normalize_money(data) do
    currency = Map.get(data, "currency")
    amount = Map.get(data, "amount")

    case Money.new(currency, amount) do
      %Money{} = money -> {:ok, Map.put(data, "amount", money)}
      _ -> {:error, invalid_transaction_currency_error(data, currency)}
    end
  end

  defp invalid_transaction_amount_error(data, raw_amount) do
    InvalidTransactionAmountError.exception(
      raw_amount: raw_amount,
      transaction_id: Map.get(data, "transaction_id"),
      internal_transaction_id: Map.get(data, "internal_transaction_id")
    )
  end

  defp invalid_transaction_currency_error(data, raw_currency) do
    InvalidTransactionCurrencyError.exception(
      raw_currency: raw_currency,
      transaction_id: Map.get(data, "transaction_id"),
      internal_transaction_id: Map.get(data, "internal_transaction_id")
    )
  end

  @fields ~w(
    transaction_id internal_transaction_id debtor_name debtor_account
    creditor_name creditor_account amount
    booking_date value_date remittance_information_unstructured
  )

  defp extract_fields(data) do
    fields =
      data
      |> Map.take(@fields)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    Map.merge(
      %{
        debtor_name: nil,
        debtor_account: nil,
        creditor_name: nil,
        creditor_account: nil
      },
      fields
    )
  end
end
