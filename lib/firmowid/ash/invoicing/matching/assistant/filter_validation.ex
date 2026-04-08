defmodule Firmowid.Ash.Invoicing.Matching.Assistant.FilterValidation do
  @moduledoc """
  Validates and coerces search filter parameters from LLM tool calls
  into typed Ash-compatible filters.
  """
  import Ecto.Changeset

  alias Money.Currency

  @type validation_result :: {:ok, map()} | {:error, String.t()}

  @spec validate_search_filters(map()) :: validation_result()
  def validate_search_filters(params) do
    types = %{
      query: :string,
      date_from: :date,
      date_to: :date,
      amount_gt: :decimal,
      amount_lt: :decimal,
      only_unmatched: :boolean,
      currency: :string
    }

    changeset =
      {%{}, types}
      |> cast(params, Map.keys(types))
      |> validate_date_range()
      |> validate_number(:amount_gt, greater_than_or_equal_to: 0)
      |> validate_number(:amount_lt, greater_than_or_equal_to: 0)
      |> validate_amount_range()
      |> validate_currency_field()
      |> validate_currency_required_for_amounts()

    if changeset.valid? do
      {:ok, changeset.changes}
    else
      {:error, format_errors(changeset)}
    end
  end

  @spec validate_normalize_to_pln(map()) :: validation_result()
  def validate_normalize_to_pln(params) do
    types = %{
      amount: :decimal,
      currency: :string,
      date: :date
    }

    changeset =
      {%{}, types}
      |> cast(params, [:amount, :currency, :date])
      |> validate_required([:amount, :currency, :date])
      |> validate_currency_field()

    if changeset.valid? do
      {:ok, changeset.changes}
    else
      {:error, format_errors(changeset)}
    end
  end

  @spec validate_calculate(map()) :: validation_result()
  def validate_calculate(params) do
    types = %{
      numbers: {:array, :decimal},
      operation: :string
    }

    changeset =
      {%{}, types}
      |> cast(params, [:numbers, :operation])
      |> validate_required([:numbers, :operation])

    if changeset.valid? do
      {:ok, changeset.changes}
    else
      {:error, format_errors(changeset)}
    end
  end

  defp validate_date_range(changeset) do
    date_from = get_change(changeset, :date_from)
    date_to = get_change(changeset, :date_to)

    with date_from when not is_nil(date_from) <- date_from,
         date_to when not is_nil(date_to) <- date_to do
      if Date.after?(date_from, date_to) do
        add_error(changeset, :date_from, "date_from musi być wcześniejsza lub równa date_to")
      else
        changeset
      end
    else
      _ -> changeset
    end
  end

  defp validate_amount_range(changeset) do
    amount_gt = get_change(changeset, :amount_gt)
    amount_lt = get_change(changeset, :amount_lt)

    with amount_gt when not is_nil(amount_gt) <- amount_gt,
         amount_lt when not is_nil(amount_lt) <- amount_lt do
      if Decimal.compare(amount_gt, amount_lt) == :gt do
        add_error(changeset, :amount_gt, "amount_gt musi być mniejsze lub równe amount_lt")
      else
        changeset
      end
    else
      _ -> changeset
    end
  end

  defp validate_currency_field(changeset) do
    validate_change(changeset, :currency, fn _field, value ->
      case value do
        value when not is_nil(value) ->
          try do
            atom_code = String.to_existing_atom(value)

            if atom_code in Currency.known_current_currencies() do
              []
            else
              [{:currency, "Nieprawidłowy kod waluty"}]
            end
          rescue
            ArgumentError -> [{:currency, "Nieprawidłowy kod waluty"}]
          end

        _ ->
          []
      end
    end)
  end

  defp validate_currency_required_for_amounts(changeset) do
    amount_gt = get_change(changeset, :amount_gt)
    amount_lt = get_change(changeset, :amount_lt)
    currency = get_change(changeset, :currency)

    has_amount_filter =
      not is_nil(amount_gt) or not is_nil(amount_lt)

    has_currency = not is_nil(currency)

    if has_amount_filter and not has_currency do
      add_error(changeset, :currency, "Waluta jest wymagana przy filtrowaniu po kwocie")
    else
      changeset
    end
  end

  defp format_errors(changeset) do
    Enum.map_join(changeset.errors, ", ", fn
      {field, {message, _opts}} -> "#{field}: #{message}"
      {_field, message} when is_binary(message) -> message
    end)
  end
end
