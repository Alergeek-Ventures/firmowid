defmodule Firmowid.Ash.Finances.DuplicateTransactionMatcher do
  @moduledoc """
  Shared matching rules for identifying duplicate-like bank transactions.

  This matcher is intentionally conservative and only returns a match when there
  is exactly one confident candidate.
  """

  alias Firmowid.Ash.Finances.TransactionDirection

  @date_tolerance_days 1
  @plain_card_replay_inserted_at_gap_days 7
  @nest_bank_institution_id "NEST_BANK_CORPORATE_NESBPLPW"

  @type transaction_like :: map() | struct()

  @spec matching_candidates(transaction_like(), [transaction_like()], keyword()) ::
          [transaction_like()]
  def matching_candidates(transaction, candidates, opts \\ []) do
    candidates
    |> Enum.reject(&same_identity?(&1, transaction))
    |> Enum.filter(&candidate_match?(&1, transaction, opts))
  end

  @spec unique_match(transaction_like(), [transaction_like()], keyword()) ::
          transaction_like() | nil
  def unique_match(transaction, candidates, opts \\ []) do
    transaction
    |> matching_candidates(candidates, opts)
    |> narrow_by_exact_date_pair(transaction)
    |> case do
      [matched_transaction] -> matched_transaction
      _ -> nil
    end
  end

  defp narrow_by_exact_date_pair([], _transaction), do: []
  defp narrow_by_exact_date_pair([candidate], _transaction), do: [candidate]

  defp narrow_by_exact_date_pair(candidates, transaction) do
    exact_matches =
      Enum.filter(candidates, &same_exact_date_pair?(&1, transaction))

    case exact_matches do
      [] -> candidates
      [_single_match] -> exact_matches
      _multiple_matches -> candidates
    end
  end

  defp same_exact_date_pair?(left, right) do
    parse_date(get_field(left, :booking_date)) == parse_date(get_field(right, :booking_date)) and
      parse_date(get_field(left, :value_date)) == parse_date(get_field(right, :value_date))
  end

  @spec candidate_match?(transaction_like(), transaction_like(), keyword()) :: boolean()
  def candidate_match?(left, right, opts \\ []) do
    same_amount?(left, right) and
      same_currency?(left, right) and
      same_counterparty_fields?(left, right, opts) and
      dates_within_tolerance?(left, right, opts) and
      remittance_matches?(left, right, opts)
  end

  @spec replay_reference_date(transaction_like()) :: Date.t() | nil
  def replay_reference_date(transaction) do
    transaction
    |> get_field(:booking_date)
    |> parse_date()
    |> case do
      nil -> parse_date(get_field(transaction, :value_date))
      date -> date
    end
  end

  @spec within_candidate_date_bounds?(
          transaction_like(),
          Date.t() | nil,
          Date.t() | nil,
          keyword()
        ) ::
          boolean()
  def within_candidate_date_bounds?(transaction, oldest_date, newest_date, opts \\ [])

  def within_candidate_date_bounds?(_transaction, nil, nil, _opts), do: true

  def within_candidate_date_bounds?(transaction, oldest_date, newest_date, opts) do
    date_tolerance_days = Keyword.get(opts, :date_tolerance_days, @date_tolerance_days)

    transaction
    |> candidate_bound_dates()
    |> case do
      [] ->
        true

      dates ->
        Enum.any?(dates, fn date ->
          Date.compare(date, Date.add(oldest_date, -date_tolerance_days)) != :lt and
            Date.compare(date, Date.add(newest_date, date_tolerance_days)) != :gt
        end)
    end
  end

  @spec normalize_remittance(term()) :: String.t()
  def normalize_remittance(value) do
    value
    |> normalize_text()
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/[[:punct:]]+/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @spec normalize_text(term()) :: String.t()
  def normalize_text(nil), do: ""

  def normalize_text(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.trim()
  end

  defp same_identity?(left, right) do
    get_field(left, :internal_transaction_id) == get_field(right, :internal_transaction_id)
  end

  defp same_amount?(left, right) do
    case {get_field(left, :amount), get_field(right, :amount)} do
      {%Money{} = left_amount, %Money{} = right_amount} ->
        Decimal.eq?(Money.to_decimal(left_amount), Money.to_decimal(right_amount))

      _other ->
        false
    end
  end

  defp same_currency?(left, right) do
    case {get_field(left, :amount), get_field(right, :amount)} do
      {%Money{} = left_amount, %Money{} = right_amount} ->
        left_amount |> Money.to_currency_code() |> Atom.to_string() |> normalize_text() ==
          right_amount |> Money.to_currency_code() |> Atom.to_string() |> normalize_text()

      _other ->
        false
    end
  end

  defp same_counterparty_fields?(left, right, opts) do
    if Keyword.get(opts, :external_counterparty_only?, false) do
      same_external_counterparty_fields?(left, right, opts)
    else
      same_all_counterparty_fields?(left, right)
    end
  end

  defp same_all_counterparty_fields?(left, right) do
    comparable_field?(get_field(left, :debtor_name), get_field(right, :debtor_name)) and
      comparable_field?(get_field(left, :debtor_account), get_field(right, :debtor_account)) and
      comparable_field?(get_field(left, :creditor_name), get_field(right, :creditor_name)) and
      comparable_field?(get_field(left, :creditor_account), get_field(right, :creditor_account))
  end

  defp same_external_counterparty_fields?(left, right, opts) do
    case account_aware_directions(left, right, opts) do
      {:available, direction, direction} when direction in [:income, :expense] ->
        same_external_counterparty_fields_for_direction?(left, right, direction)

      {:available, _left_direction, _right_direction} ->
        false

      :unavailable ->
        same_external_counterparty_fields_by_sign?(left, right)
    end
  end

  defp same_external_counterparty_fields_for_direction?(left, right, :income) do
    comparable_field?(get_field(left, :debtor_name), get_field(right, :debtor_name)) and
      comparable_field?(get_field(left, :debtor_account), get_field(right, :debtor_account))
  end

  defp same_external_counterparty_fields_for_direction?(left, right, :expense) do
    comparable_field?(get_field(left, :creditor_name), get_field(right, :creditor_name)) and
      comparable_field?(get_field(left, :creditor_account), get_field(right, :creditor_account))
  end

  defp same_external_counterparty_fields_by_sign?(left, right) do
    case transaction_side(left) do
      :debtor ->
        comparable_field?(get_field(left, :debtor_name), get_field(right, :debtor_name)) and
          comparable_field?(get_field(left, :debtor_account), get_field(right, :debtor_account))

      :creditor ->
        comparable_field?(get_field(left, :creditor_name), get_field(right, :creditor_name)) and
          comparable_field?(
            get_field(left, :creditor_account),
            get_field(right, :creditor_account)
          )

      :both ->
        same_all_counterparty_fields?(left, right)
    end
  end

  defp account_aware_directions(left, right, opts) do
    case Keyword.get(opts, :connected_account_iban) do
      iban when is_binary(iban) and iban != "" ->
        {:available, TransactionDirection.direction(left, iban), TransactionDirection.direction(right, iban)}

      _other ->
        :unavailable
    end
  end

  defp transaction_side(transaction) do
    case Decimal.compare(Money.to_decimal(get_field(transaction, :amount)), Decimal.new(0)) do
      :gt -> :debtor
      :lt -> :creditor
      :eq -> :both
    end
  end

  defp comparable_field?(left, right), do: normalize_text(left) == normalize_text(right)

  defp dates_within_tolerance?(left, right, opts) do
    date_tolerance_days = Keyword.get(opts, :date_tolerance_days, @date_tolerance_days)

    case comparable_date_pairs(left, right) do
      [] -> true
      date_pairs -> Enum.any?(date_pairs, &dates_within_tolerance?(&1, date_tolerance_days))
    end
  end

  defp remittance_matches?(left, right, opts) do
    left_raw_remittance = to_string(get_field(left, :remittance_information_unstructured))
    right_raw_remittance = to_string(get_field(right, :remittance_information_unstructured))

    left_remittance = normalize_remittance(get_field(left, :remittance_information_unstructured))

    right_remittance =
      normalize_remittance(get_field(right, :remittance_information_unstructured))

    cond do
      exact_remittance_match?(
        left,
        right,
        left_remittance,
        right_remittance,
        left_raw_remittance,
        right_raw_remittance,
        opts
      ) ->
        true

      left_remittance == "" or right_remittance == "" ->
        false

      nest_bank_remittance_match?(left, right, opts) ->
        true

      true ->
        false
    end
  end

  defp exact_remittance_match?(
         left,
         right,
         left_remittance,
         right_remittance,
         left_raw_remittance,
         right_raw_remittance,
         opts
       ) do
    left_remittance == right_remittance and
      plain_nest_bank_card_remittance_match_allowed?(
        left,
        right,
        left_remittance,
        left_raw_remittance,
        right_raw_remittance,
        opts
      )
  end

  defp plain_nest_bank_card_remittance_match_allowed?(
         left,
         right,
         remittance,
         left_raw_remittance,
         right_raw_remittance,
         opts
       ) do
    not plain_nest_bank_card_remittance?(
      remittance,
      left_raw_remittance,
      right_raw_remittance,
      opts
    ) or plain_nest_bank_card_replay_match?(left, right, opts)
  end

  defp nest_bank_remittance_match?(left, right, opts) do
    nest_bank_institution?(opts) and prefixed_remittance_match?(left, right)
  end

  defp nest_bank_institution?(opts) do
    Keyword.get(opts, :institution_id) == @nest_bank_institution_id
  end

  defp plain_nest_bank_card_remittance?(remittance, left_raw_remittance, right_raw_remittance, opts) do
    nest_bank_institution?(opts) and String.starts_with?(remittance, "nr karty") and
      not nest_bank_fx_card_remittance?(left_raw_remittance) and
      not nest_bank_fx_card_remittance?(right_raw_remittance)
  end

  defp plain_nest_bank_card_replay_match?(left, right, opts) do
    left_remittance = normalize_remittance(get_field(left, :remittance_information_unstructured))

    right_remittance =
      normalize_remittance(get_field(right, :remittance_information_unstructured))

    left_remittance == right_remittance and
      plain_nest_bank_card_remittance?(
        left_remittance,
        to_string(get_field(left, :remittance_information_unstructured)),
        to_string(get_field(right, :remittance_information_unstructured)),
        opts
      ) and inserted_at_gap_large_enough?(left, right) and
      plain_nest_bank_card_replay_dates_within_tolerance?(left, right, opts)
  end

  defp inserted_at_gap_large_enough?(left, right) do
    case {parse_naive_datetime(get_field(left, :inserted_at)), parse_naive_datetime(get_field(right, :inserted_at))} do
      {nil, _right_inserted_at} ->
        false

      {_left_inserted_at, nil} ->
        false

      {left_inserted_at, right_inserted_at} ->
        abs(NaiveDateTime.diff(left_inserted_at, right_inserted_at, :day)) >=
          @plain_card_replay_inserted_at_gap_days
    end
  end

  defp plain_nest_bank_card_replay_dates_within_tolerance?(left, right, opts) do
    date_tolerance_days = Keyword.get(opts, :date_tolerance_days, @date_tolerance_days)

    left_booking_date = parse_date(get_field(left, :booking_date))
    left_value_date = parse_date(get_field(left, :value_date))
    right_booking_date = parse_date(get_field(right, :booking_date))
    right_value_date = parse_date(get_field(right, :value_date))

    Enum.any?(
      Enum.reject(
        [
          {left_booking_date, right_booking_date},
          {left_value_date, right_value_date}
        ],
        fn {left_date, right_date} -> is_nil(left_date) or is_nil(right_date) end
      ),
      &dates_within_tolerance?(&1, date_tolerance_days)
    )
  end

  defp nest_bank_fx_card_remittance?(remittance) do
    Regex.match?(~r/\b\d+[,\.]\d{2}[A-Z]{3}\s+\d+[,\.]\d{4}\b/i, remittance)
  end

  defp comparable_date_pairs(left, right) do
    left_booking_date = parse_date(get_field(left, :booking_date))
    left_value_date = parse_date(get_field(left, :value_date))
    right_booking_date = parse_date(get_field(right, :booking_date))
    right_value_date = parse_date(get_field(right, :value_date))

    Enum.reject(
      [
        {left_booking_date, right_booking_date},
        {left_booking_date, right_value_date},
        {left_value_date, right_booking_date}
      ],
      fn {left_date, right_date} -> is_nil(left_date) or is_nil(right_date) end
    )
  end

  defp candidate_bound_dates(transaction) do
    [
      parse_date(get_field(transaction, :booking_date)),
      parse_date(get_field(transaction, :value_date))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp dates_within_tolerance?({left_date, right_date}, date_tolerance_days) do
    abs(Date.diff(left_date, right_date)) <= date_tolerance_days
  end

  defp prefixed_remittance_match?(left, right) do
    left_remittance = normalize_remittance(get_field(left, :remittance_information_unstructured))

    right_remittance =
      normalize_remittance(get_field(right, :remittance_information_unstructured))

    prefixed_remittance_suffix(left) == right_remittance or
      prefixed_remittance_suffix(right) == left_remittance
  end

  defp prefixed_remittance_suffix(transaction) do
    transaction
    |> get_field(:remittance_information_unstructured)
    |> to_string()
    |> String.split(",", parts: 2)
    |> case do
      [_prefix, suffix] -> normalize_remittance(suffix)
      _other -> ""
    end
  end

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_), do: nil

  defp parse_naive_datetime(%NaiveDateTime{} = datetime), do: datetime

  defp parse_naive_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_naive_datetime(_), do: nil

  defp get_field(%_{} = struct, field), do: Map.get(struct, field)
  defp get_field(map, field) when is_map(map), do: Map.get(map, field)
end
