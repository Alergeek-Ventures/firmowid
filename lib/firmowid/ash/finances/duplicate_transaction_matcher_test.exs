defmodule Firmowid.Ash.Finances.DuplicateTransactionMatcherTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Finances.DuplicateTransactionMatcher

  @nest_bank_institution_id "NEST_BANK_CORPORATE_NESBPLPW"
  @subscription_card_creditor_name "example-subscription.test Demo City"
  @subscription_card_creditor_account "PL11111111111111111111111111"
  @subscription_card_debtor_name "EXAMPLE COMPANY SP Z O O"
  @subscription_card_debtor_account "PL22222222222222222222222222"

  @subscription_card_expected_rows [
    {~D[2026-04-23], ~D[2026-04-20], "-50"},
    {~D[2026-04-20], ~D[2026-04-17], "-20"},
    {~D[2026-04-18], ~D[2026-04-15], "-10"},
    {~D[2026-04-15], ~D[2026-04-12], "-25"},
    {~D[2026-04-03], ~D[2026-03-31], "-10"},
    {~D[2026-04-01], ~D[2026-03-29], "-25"},
    {~D[2026-03-30], ~D[2026-03-27], "-10"},
    {~D[2026-03-24], ~D[2026-03-21], "-20"},
    {~D[2026-03-20], ~D[2026-03-17], "-20"},
    {~D[2026-03-19], ~D[2026-03-16], "-20"},
    {~D[2026-03-17], ~D[2026-03-13], "-5"},
    {~D[2026-03-17], ~D[2026-03-12], "-25"},
    {~D[2026-03-11], ~D[2026-03-08], "-10"},
    {~D[2026-03-05], ~D[2026-03-02], "-10"},
    {~D[2026-03-02], ~D[2026-02-27], "-10"},
    {~D[2026-03-01], ~D[2026-02-26], "-25"},
    {~D[2026-02-28], ~D[2026-02-25], "-10"},
    {~D[2026-02-17], ~D[2026-02-14], "-20"},
    {~D[2026-02-16], ~D[2026-02-13], "-25"},
    {~D[2026-02-16], ~D[2026-02-13], "-5"},
    {~D[2026-02-12], ~D[2026-02-09], "-25"},
    {~D[2026-02-07], ~D[2026-02-04], "-10"},
    {~D[2026-02-03], ~D[2026-01-30], "-10"},
    {~D[2026-01-30], ~D[2026-01-27], "-10"},
    {~D[2026-01-29], ~D[2026-01-26], "-25"},
    {~D[2026-01-23], ~D[2026-01-20], "-30"},
    {~D[2026-01-17], ~D[2026-01-14], "-20"},
    {~D[2026-01-12], ~D[2026-01-09], "-20"},
    {~D[2026-01-12], ~D[2026-01-09], "-25"},
    {~D[2026-01-08], ~D[2026-01-05], "-10"},
    {~D[2026-01-05], ~D[2026-01-02], "-10"}
  ]

  @subscription_card_imported_rows [
    {:historical, ~D[2026-03-31], ~D[2026-03-28], "-25", ~N[2026-04-01 10:00:23]},
    {:historical, ~D[2026-03-04], ~D[2026-03-01], "-10", ~N[2026-03-09 14:04:44]},
    {:historical, ~D[2026-03-18], ~D[2026-03-15], "-20", ~N[2026-03-19 11:00:21]},
    {:historical, ~D[2026-01-16], ~D[2026-01-13], "-20.00", ~N[2026-01-19 20:52:29]},
    {:historical, ~D[2026-01-11], ~D[2026-01-08], "-20.00", ~N[2026-01-13 11:00:05]},
    {:historical, ~D[2026-03-16], ~D[2026-03-12], "-5", ~N[2026-03-17 11:00:29]},
    {:historical, ~D[2026-03-19], ~D[2026-03-16], "-20", ~N[2026-03-21 11:00:19]},
    {:historical, ~D[2026-03-16], ~D[2026-03-11], "-25", ~N[2026-03-17 11:00:29]},
    {:historical, ~D[2026-03-29], ~D[2026-03-26], "-10", ~N[2026-03-30 15:37:57]},
    {:historical, ~D[2026-03-23], ~D[2026-03-20], "-20", ~N[2026-03-25 11:00:23]},
    {:historical, ~D[2026-03-10], ~D[2026-03-07], "-10", ~N[2026-03-11 11:00:23]},
    {:historical, ~D[2026-02-28], ~D[2026-02-25], "-25", ~N[2026-03-02 17:01:01]},
    {:historical, ~D[2026-03-01], ~D[2026-02-26], "-10", ~N[2026-03-02 17:01:01]},
    {:historical, ~D[2026-02-27], ~D[2026-02-24], "-10", ~N[2026-03-02 17:01:01]},
    {:historical, ~D[2026-02-16], ~D[2026-02-13], "-20", ~N[2026-02-17 11:00:08]},
    {:historical, ~D[2026-02-15], ~D[2026-02-12], "-25", ~N[2026-02-17 11:00:08]},
    {:historical, ~D[2026-02-15], ~D[2026-02-12], "-5", ~N[2026-02-17 11:00:08]},
    {:historical, ~D[2026-02-11], ~D[2026-02-08], "-25", ~N[2026-02-17 11:00:08]},
    {:historical, ~D[2026-02-06], ~D[2026-02-03], "-10", ~N[2026-02-11 12:16:36]},
    {:historical, ~D[2026-02-02], ~D[2026-01-29], "-10", ~N[2026-02-03 11:38:23]},
    {:historical, ~D[2026-01-04], ~D[2026-01-01], "-10.00", ~N[2026-01-07 11:00:05]},
    {:historical, ~D[2026-01-29], ~D[2026-01-26], "-10", ~N[2026-01-31 11:00:08]},
    {:historical, ~D[2026-01-28], ~D[2026-01-25], "-25", ~N[2026-01-31 11:00:08]},
    {:historical, ~D[2026-01-22], ~D[2026-01-19], "-30.00", ~N[2026-01-23 11:00:09]},
    {:historical, ~D[2026-01-11], ~D[2026-01-08], "-25.00", ~N[2026-01-13 11:00:05]},
    {:historical, ~D[2026-01-07], ~D[2026-01-04], "-10.00", ~N[2026-01-09 15:44:20]},
    {:replay, ~D[2026-04-23], ~D[2026-04-20], "-50.00", ~N[2026-04-23 10:10:09]},
    {:replay, ~D[2026-04-20], ~D[2026-04-17], "-20.00", ~N[2026-04-23 10:10:09]},
    {:replay, ~D[2026-04-18], ~D[2026-04-15], "-10.00", ~N[2026-04-23 10:10:09]},
    {:replay, ~D[2026-04-15], ~D[2026-04-12], "-25.00", ~N[2026-04-23 10:10:09]},
    {:replay, ~D[2026-04-03], ~D[2026-03-31], "-10.00", ~N[2026-04-23 10:10:09]},
    {:historical, ~D[2026-04-02], ~D[2026-03-30], "-10", ~N[2026-04-03 10:00:19]},
    {:replay, ~D[2026-04-01], ~D[2026-03-29], "-25.00", ~N[2026-04-23 10:10:09]},
    {:replay, ~D[2026-03-30], ~D[2026-03-27], "-10.00", ~N[2026-04-23 10:10:09]},
    {:replay, ~D[2026-03-24], ~D[2026-03-21], "-20.00", ~N[2026-04-23 10:10:09]}
  ]

  describe "unique_match/2" do
    test "matches NestBank remittance when one side has a payer prefix before a comma" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          remittance_information_unstructured: "Usługi informatyczne Faktura 07/02/2026",
          booking_date: ~D[2026-04-20]
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          remittance_information_unstructured: "PRZYKŁADOWY NADAWCA, Usługi informatyczne Faktura 07/02/2026",
          booking_date: ~D[2026-04-20]
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing],
               institution_id: "NEST_BANK_CORPORATE_NESBPLPW"
             ) == existing
    end

    test "does not use NestBank prefix heuristic for other institutions" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          remittance_information_unstructured: "Usługi informatyczne Faktura 07/02/2026",
          booking_date: ~D[2026-04-20]
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          remittance_information_unstructured: "PRZYKŁADOWY NADAWCA, Usługi informatyczne Faktura 07/02/2026",
          booking_date: ~D[2026-04-20]
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing], institution_id: "OTHER_BANK") == nil
    end

    test "matches NestBank remittance when company name is prefixed before a comma" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          remittance_information_unstructured: "F83145018/26",
          booking_date: ~D[2026-04-20]
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          remittance_information_unstructured: "Orange Polska S.A., F83145018/26",
          booking_date: ~D[2026-04-20]
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing],
               institution_id: "NEST_BANK_CORPORATE_NESBPLPW"
             ) == existing
    end

    test "does not match remittances with different numeric references" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          remittance_information_unstructured: "Opłata za przelew nr 000022"
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          remittance_information_unstructured: "Opłata za przelew nr 000023"
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing]) == nil
    end

    test "does not match clearly different invoice references" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          remittance_information_unstructured: "PŁATNOŚĆ ZA FAKTURĘ 583/B/2025"
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          remittance_information_unstructured: "PŁATNOŚĆ ZA FAKTURĘ 34/B/2026"
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing]) == nil
    end

    test "matches when incoming booking date is within one day of existing value date" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          booking_date: ~D[2026-04-18],
          value_date: ~D[2026-04-20]
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          booking_date: ~D[2026-04-21],
          value_date: ~D[2026-04-25]
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing]) == existing
    end

    test "does not match plain NestBank card remittances without FX anchor" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          remittance_information_unstructured: "Nr karty  ...1111 10,00PLN",
          creditor_name: "example-subscription.test Demo City"
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          remittance_information_unstructured: "Nr karty  ...1111 10,00PLN",
          creditor_name: "example-subscription.test Demo City"
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing],
               institution_id: "NEST_BANK_CORPORATE_NESBPLPW"
             ) == nil
    end

    test "matches NestBank card remittances with FX anchor" do
      existing =
        transaction(%{
          internal_transaction_id: "existing-id",
          remittance_information_unstructured: "Nr karty  ...1111 182,90USD 3,9370",
          creditor_name: "SLACK T039H6L5J2U DUBLIN 1"
        })

      incoming =
        transaction(%{
          internal_transaction_id: "incoming-id",
          remittance_information_unstructured: "Nr karty  ...1111 182,90USD 3,9370",
          creditor_name: "SLACK T039H6L5J2U DUBLIN 1"
        })

      assert DuplicateTransactionMatcher.unique_match(incoming, [existing],
               institution_id: "NEST_BANK_CORPORATE_NESBPLPW"
             ) == existing
    end

    test "returns nil for ambiguous duplicate candidates" do
      candidate_1 = transaction(%{internal_transaction_id: "candidate-1"})
      candidate_2 = transaction(%{internal_transaction_id: "candidate-2"})
      incoming = transaction(%{internal_transaction_id: "incoming-id"})

      assert DuplicateTransactionMatcher.unique_match(incoming, [candidate_1, candidate_2]) == nil
    end

    test "does not collapse plain Subscription NestBank card rows within a single generation" do
      imported_transactions = subscription_card_imported_transactions()

      historical_transactions =
        Enum.filter(
          imported_transactions,
          &NaiveDateTime.before?(&1.inserted_at, ~N[2026-04-23 00:00:00])
        )

      deduped_transactions =
        Enum.reduce(historical_transactions, [], fn transaction, canonical_transactions ->
          case DuplicateTransactionMatcher.matching_candidates(
                 transaction,
                 canonical_transactions,
                 institution_id: @nest_bank_institution_id
               ) do
            [] -> canonical_transactions ++ [transaction]
            [_matched_transaction] -> canonical_transactions
            _ambiguous_candidates -> canonical_transactions ++ [transaction]
          end
        end)

      assert length(deduped_transactions) == length(historical_transactions)
    end

    test "keeps Subscription prod import flow aligned with bank statement count" do
      imported_transactions = subscription_card_imported_transactions()

      {existing_transactions, newly_imported_transactions} =
        Enum.split_with(
          imported_transactions,
          &NaiveDateTime.before?(&1.inserted_at, ~N[2026-04-23 00:00:00])
        )

      final_transactions =
        Enum.reduce(newly_imported_transactions, existing_transactions, fn transaction, canonical_transactions ->
          case DuplicateTransactionMatcher.matching_candidates(
                 transaction,
                 canonical_transactions,
                 institution_id: @nest_bank_institution_id
               ) do
            [] -> canonical_transactions ++ [transaction]
            [_matched_transaction] -> canonical_transactions
            _ambiguous_candidates -> canonical_transactions ++ [transaction]
          end
        end)

      expected_transactions = subscription_card_expected_transactions()

      final_count = length(final_transactions)
      expected_count = length(expected_transactions)
      extra_survivors = subscription_signature_diff(final_transactions, expected_transactions)
      missing_survivors = subscription_signature_diff(expected_transactions, final_transactions)
      extra_survivor_signatures = Enum.map(extra_survivors, &elem(&1, 0))

      assert final_count == expected_count,
             """
             Subscription prod-flow count mismatch

             Final imported count: #{final_count}
             Bank statement count: #{expected_count}

             Final amount counts:
             #{format_subscription_amount_counts(final_transactions)}

             Expected amount counts:
             #{format_subscription_amount_counts(expected_transactions)}

             Extra survivor groups:
             #{format_subscription_signature_diff(extra_survivors)}

             Extra survivor row details:
             #{format_subscription_signature_rows(final_transactions, expected_transactions, extra_survivor_signatures)}

             Missing survivor groups:
             #{format_subscription_signature_diff(missing_survivors)}
             """
    end
  end

  describe "matching_candidates/2" do
    test "returns all ambiguous candidates for logging or review" do
      candidate_1 = transaction(%{internal_transaction_id: "candidate-1"})
      candidate_2 = transaction(%{internal_transaction_id: "candidate-2"})
      incoming = transaction(%{internal_transaction_id: "incoming-id"})

      assert DuplicateTransactionMatcher.matching_candidates(incoming, [candidate_1, candidate_2]) ==
               [candidate_1, candidate_2]
    end
  end

  describe "within_candidate_date_bounds?/3" do
    test "keeps transactions within tolerance around incoming batch bounds" do
      transaction = transaction(%{booking_date: ~D[2026-04-11]})

      assert DuplicateTransactionMatcher.within_candidate_date_bounds?(
               transaction,
               ~D[2026-04-11],
               ~D[2026-04-12]
             )
    end

    test "keeps transactions when value date is within bounds even if booking date is outside" do
      transaction =
        transaction(%{
          booking_date: ~D[2026-04-25],
          value_date: ~D[2026-04-12]
        })

      assert DuplicateTransactionMatcher.within_candidate_date_bounds?(
               transaction,
               ~D[2026-04-11],
               ~D[2026-04-12]
             )
    end
  end

  defp transaction(overrides) do
    Map.merge(
      %{
        internal_transaction_id: "default-id",
        amount: Money.new!("PLN", Decimal.new("100.00")),
        debtor_name: "Example Debtor",
        debtor_account: "PL001",
        creditor_name: "Example Creditor",
        creditor_account: "PL002",
        booking_date: ~D[2026-04-20],
        value_date: ~D[2026-04-20],
        remittance_information_unstructured: "Example remittance"
      },
      overrides
    )
  end

  defp subscription_card_imported_transactions do
    @subscription_card_imported_rows
    |> Enum.with_index(1)
    |> Enum.map(fn {{generation, booking_date, value_date, amount, inserted_at}, index} ->
      %{
        id: "fixture-id-#{index}",
        transaction_id: "fixture-transaction-#{index}",
        internal_transaction_id: "fixture-internal-#{index}",
        creditor_name: @subscription_card_creditor_name,
        creditor_account: @subscription_card_creditor_account,
        debtor_name: @subscription_card_debtor_name,
        debtor_account: @subscription_card_debtor_account,
        amount: Money.new!("PLN", Decimal.new(amount)),
        booking_date: booking_date,
        value_date: value_date,
        remittance_information_unstructured: subscription_card_remittance(amount),
        inserted_at: inserted_at,
        generation: generation
      }
    end)
  end

  defp subscription_card_expected_transactions do
    Enum.map(@subscription_card_expected_rows, fn {booking_date, value_date, amount} ->
      %{
        booking_date: booking_date,
        value_date: value_date,
        amount: Money.new!("PLN", Decimal.new(amount)),
        creditor_name: @subscription_card_creditor_name,
        remittance_information_unstructured: subscription_card_remittance(amount)
      }
    end)
  end

  defp subscription_card_remittance(amount) do
    normalized_amount =
      amount
      |> Decimal.new()
      |> Decimal.abs()
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)
      |> String.replace(".", ",")

    "Nr karty  ...1111 #{normalized_amount}PLN"
  end

  defp format_subscription_amount_counts(transactions) do
    transactions
    |> Enum.group_by(&normalize_subscription_amount(Money.to_decimal(&1.amount)))
    |> Enum.sort_by(fn {amount, _transactions} -> amount end)
    |> Enum.map_join("\n", fn {amount, grouped_transactions} ->
      "- amount=#{amount} count=#{length(grouped_transactions)}"
    end)
  end

  defp subscription_signature_diff(left_transactions, right_transactions) do
    left_counts = subscription_signature_counts(left_transactions)
    right_counts = subscription_signature_counts(right_transactions)

    left_counts
    |> Enum.map(fn {signature, left_count} ->
      {signature, max(left_count - Map.get(right_counts, signature, 0), 0)}
    end)
    |> Enum.reject(fn {_signature, count} -> count == 0 end)
    |> Enum.sort_by(fn {{amount, _currency, creditor_name, remittance}, _count} ->
      {amount, creditor_name, remittance}
    end)
  end

  defp subscription_signature_counts(transactions) do
    Enum.frequencies_by(transactions, &subscription_signature/1)
  end

  defp subscription_signature(transaction) do
    {
      normalize_subscription_amount(Money.to_decimal(transaction.amount)),
      transaction.amount |> Money.to_currency_code() |> Atom.to_string(),
      transaction.creditor_name,
      transaction.remittance_information_unstructured
    }
  end

  defp normalize_subscription_amount(amount) do
    amount
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp format_subscription_signature_diff([]), do: "- none"

  defp format_subscription_signature_diff(diff_entries) do
    Enum.map_join(
      diff_entries,
      "\n",
      fn {{amount, currency, creditor_name, remittance}, count} ->
        "- count=#{count} amount=#{amount} #{currency} creditor=#{creditor_name} remittance=#{inspect(remittance)}"
      end
    )
  end

  defp format_subscription_signature_rows(_final_transactions, _expected_transactions, []), do: "- none"

  defp format_subscription_signature_rows(final_transactions, expected_transactions, signatures) do
    Enum.map_join(signatures, "\n\n", fn signature ->
      """
      Signature #{format_subscription_signature(signature)}
      Final rows:
      #{format_subscription_row_list(filter_subscription_signature(final_transactions, signature))}
      Expected rows:
      #{format_subscription_row_list(filter_subscription_signature(expected_transactions, signature))}
      """
    end)
  end

  defp filter_subscription_signature(transactions, signature) do
    transactions
    |> Enum.filter(&(subscription_signature(&1) == signature))
    |> Enum.sort_by(fn transaction ->
      {
        transaction.booking_date,
        transaction.value_date,
        Map.get(transaction, :inserted_at),
        Map.get(transaction, :internal_transaction_id),
        Map.get(transaction, :id)
      }
    end)
  end

  defp format_subscription_row_list([]), do: "- none"

  defp format_subscription_row_list(transactions) do
    Enum.map_join(transactions, "\n", &format_subscription_row/1)
  end

  defp format_subscription_row(transaction) do
    Enum.join(
      [
        "- booking_date=#{Map.get(transaction, :booking_date)}",
        "value_date=#{Map.get(transaction, :value_date)}",
        "inserted_at=#{Map.get(transaction, :inserted_at)}",
        "internal_transaction_id=#{inspect(Map.get(transaction, :internal_transaction_id))}",
        "id=#{inspect(Map.get(transaction, :id))}"
      ],
      " "
    )
  end

  defp format_subscription_signature({amount, currency, creditor_name, remittance}) do
    "amount=#{amount} #{currency} creditor=#{creditor_name} remittance=#{inspect(remittance)}"
  end
end
