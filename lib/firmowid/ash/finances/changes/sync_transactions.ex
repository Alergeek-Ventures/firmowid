defmodule Firmowid.Ash.Finances.Changes.SyncTransactions do
  @moduledoc """
  Ash.Resource.Change that syncs transactions from GoCardless.

  1. Fetches booked transactions via `ApiClient` (with automatic token refresh)
  2. Parses them using `TransactionParser`
  3. Upserts them via `Ash.bulk_create` to the Transaction resource

  ## Requisition Expiration Detection

  When GoCardless returns `:expired_eua`, this change expires the parent
  requisition via `Requisition.expire/2` — the reactive path for detecting
  expired connections.
  """
  use Ash.Resource.Change

  import Ash.Expr

  alias Firmowid.Ash.Events
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.DuplicateTransactionMatcher
  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.Ash.Finances.GoCardless.TransactionParser
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Finances.TransactionDirection
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind
  alias Firmowid.Sentry

  require Logger

  @sync_replay_buffer_days 7
  @sync_replay_min_days 14
  @sync_replay_max_days 90
  @sync_candidate_date_tolerance_days 1
  @impl true
  def change(changeset, _opts, _context) do
    sync_started_at = DateTime.utc_now()

    Ash.Changeset.after_action(changeset, fn changeset, bank_account ->
      case perform_sync(bank_account, build_sync_scope(bank_account), sync_started_at) do
        {:ok, _} ->
          {:ok, bank_account}

        {:error, reason} ->
          {:error, Ash.Changeset.add_error(changeset, "sync failed: #{ErrorKind.classify(reason)}")}
      end
    end)
  end

  defp perform_sync(bank_account, scope, sync_started_at) do
    with {:ok, previous_successful_sync_at} <-
           previous_successful_sync_at(bank_account, scope, sync_started_at),
         {:ok, booked} <- fetch_transactions(bank_account),
         :ok <- upsert_transactions(booked, bank_account, previous_successful_sync_at, scope) do
      {:ok, bank_account}
    else
      {:error, :expired_eua} ->
        with :ok <- expire_parent_requisition(bank_account, scope) do
          {:ok, bank_account}
        end

      error ->
        error
    end
  end

  defp fetch_transactions(bank_account) do
    ApiClient.with_token_refresh(fn ->
      ApiClient.get_booked_transactions_for_account(bank_account.gocardless_id)
    end)
  end

  defp expire_parent_requisition(bank_account, scope) do
    case bank_account.requisition_id do
      nil ->
        Logger.warning("Cannot expire missing requisition during sync for bank account #{bank_account.id}")

        :ok

      requisition_id ->
        requisition_id
        |> fetch_parent_requisition(scope)
        |> expire_parent_requisition_record(requisition_id, scope)
    end
  end

  defp fetch_parent_requisition(requisition_id, scope) do
    Finances.get_requisition(requisition_id,
      actor: scope.actor,
      tenant: scope.tenant,
      not_found_error?: false
    )
  end

  defp expire_parent_requisition_record({:ok, nil}, requisition_id, _scope) do
    Logger.warning("Cannot expire missing requisition #{requisition_id} during sync")
    :ok
  end

  defp expire_parent_requisition_record({:ok, requisition}, requisition_id, scope) do
    case Requisition.expire(requisition, actor: scope.actor, tenant: scope.tenant) do
      {:ok, _} ->
        Logger.info("Expired requisition #{requisition_id} during sync")
        :ok

      {:error, reason} ->
        Logger.warning(
          "Could not expire requisition #{requisition_id} during sync: error_kind=#{ErrorKind.classify(reason)}"
        )

        {:error, reason}
    end
  end

  defp expire_parent_requisition_record({:error, reason}, requisition_id, _scope) do
    if not_found_error?(reason) do
      Logger.warning("Cannot expire missing requisition #{requisition_id} during sync")
      :ok
    else
      Logger.warning("Could not load requisition #{requisition_id} during sync: error_kind=#{ErrorKind.classify(reason)}")

      {:error, reason}
    end
  end

  defp not_found_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1))
  end

  defp not_found_error?(_reason), do: false

  defp upsert_transactions(booked_transactions, bank_account, previous_successful_sync_at, scope) do
    %{transactions: parsed_transactions, errors: parse_errors} =
      TransactionParser.parse_all(booked_transactions, bank_account)

    report_parse_errors(parse_errors, bank_account)

    transactions =
      parsed_transactions
      |> Enum.map(&Map.put(&1, :bank_account_id, bank_account.id))
      |> filter_transactions_for_replay(bank_account, previous_successful_sync_at)
      |> dedupe_against_existing_transactions(bank_account, scope)
      |> dedupe_final_upsert_batch(bank_account)

    cond do
      transactions == [] and parse_errors == [] ->
        Logger.debug("No transactions returned for bank account #{bank_account.id}")
        :ok

      transactions == [] ->
        Logger.error(
          "All fetched transactions failed to parse for bank account #{bank_account.id}; " <>
            "skipped #{length(parse_errors)} invalid transactions"
        )

        {:error, {:all_transactions_invalid, length(parse_errors)}}

      true ->
        do_upsert_transactions(transactions, bank_account, scope)
    end
  end

  defp do_upsert_transactions(transactions, bank_account, scope) do
    result =
      Finances.upsert_transaction_from_sync(
        transactions,
        scope: scope,
        upsert?: true,
        actor: %SystemActor{org_id: bank_account.organization_id, role: :bank_sync},
        bulk_options: [
          return_errors?: true,
          stop_on_error?: false,
          batch_size: 100,
          notify?: true
        ]
      )

    case result do
      %{status: :success} ->
        Logger.debug("Synced transactions for bank account #{bank_account.id}")
        :ok

      %{status: :partial_success, errors: errors} ->
        Logger.warning(
          "Partial sync for bank account #{bank_account.id}: " <>
            "#{length(errors)} errors error_kinds=#{inspect(error_kinds(errors))}"
        )

        report_upsert_errors(errors, bank_account)
        :ok

      %{status: :error, errors: errors} ->
        Logger.error(
          "Failed to sync transactions for bank account #{bank_account.id}: " <>
            "stage=upsert errors=#{length(errors)} error_kinds=#{inspect(error_kinds(errors))}"
        )

        report_upsert_errors(errors, bank_account)
        {:error, :upsert_failed}
    end
  end

  defp report_parse_errors([], _bank_account), do: :ok

  defp report_parse_errors(errors, bank_account) do
    Enum.each(errors, &report_parse_error(&1, bank_account))
  end

  defp report_parse_error(error, bank_account) do
    Logger.warning(
      "Skipping GoCardless transaction for bank account #{bank_account.id}: " <>
        "stage=parse error_kind=#{ErrorKind.classify(error)}"
    )

    error_kind = ErrorKind.classify(error)

    Sentry.capture_exception(
      RuntimeError.exception("Transaction parse failed during GoCardless sync"),
      tags: %{
        source: "gocardless_transaction_sync",
        stage: "parse",
        error_kind: error_kind
      },
      extra: %{
        bank_account_id: bank_account.id,
        organization_id: bank_account.organization_id,
        requisition_id: bank_account.requisition_id,
        error_kind: error_kind
      }
    )
  rescue
    _sentry_error ->
      Logger.warning("Failed to report transaction parse error to Sentry")
  end

  defp report_upsert_errors(errors, bank_account) do
    Logger.error(
      "Transaction upsert errors for bank account #{bank_account.id}: " <>
        "stage=upsert errors=#{length(errors)} error_kinds=#{inspect(error_kinds(errors))}"
    )

    Sentry.capture_exception(
      RuntimeError.exception("Transaction upsert failed during GoCardless sync"),
      tags: %{
        source: "gocardless_transaction_sync",
        stage: "upsert"
      },
      extra: %{
        bank_account_id: bank_account.id,
        organization_id: bank_account.organization_id,
        requisition_id: bank_account.requisition_id,
        error_count: length(errors),
        error_kinds: error_kinds(errors)
      }
    )
  rescue
    _sentry_error ->
      Logger.warning("Failed to report transaction upsert error to Sentry")
  end

  defp error_kinds(errors), do: errors |> Enum.map(&ErrorKind.classify/1) |> Enum.uniq()

  defp build_sync_scope(bank_account) do
    %Scope{
      actor: %SystemActor{org_id: bank_account.organization_id, role: :bank_sync},
      tenant: bank_account.organization_id
    }
  end

  defp previous_successful_sync_at(bank_account, scope, sync_started_at) do
    Events.last_successful_sync_at(bank_account, scope: scope, before: sync_started_at)
  end

  defp filter_transactions_for_replay(transactions, _bank_account, nil), do: transactions

  defp filter_transactions_for_replay(transactions, bank_account, previous_successful_sync_at) do
    lookback_days = replay_lookback_days(previous_successful_sync_at)
    cutoff_date = Date.add(Date.utc_today(), -lookback_days)

    {kept, skipped} =
      Enum.split_with(transactions, fn transaction ->
        keep_for_replay?(transaction, cutoff_date)
      end)

    if skipped != [] do
      Logger.info(
        "Filtered #{length(skipped)} replayed transactions older than #{cutoff_date} " <>
          "for bank account #{bank_account.id} using #{lookback_days}-day window"
      )
    end

    kept
  end

  defp replay_lookback_days(latest_successful_sync_at) do
    latest_successful_sync_at
    |> DateTime.to_date()
    |> Date.diff(Date.utc_today())
    |> Kernel.*(-1)
    |> Kernel.+(@sync_replay_buffer_days)
    |> max(@sync_replay_min_days)
    |> min(@sync_replay_max_days)
  end

  defp keep_for_replay?(transaction, cutoff_date) do
    case DuplicateTransactionMatcher.replay_reference_date(transaction) do
      nil -> true
      reference_date -> Date.compare(reference_date, cutoff_date) != :lt
    end
  end

  defp dedupe_against_existing_transactions([], _bank_account, _scope), do: []

  defp dedupe_against_existing_transactions(transactions, bank_account, scope) do
    existing_transactions =
      load_existing_transactions_for_dedupe(bank_account, transactions, scope)

    connected_account_iban = bank_account.iban

    candidate_map =
      build_candidate_transaction_buckets(existing_transactions, connected_account_iban)

    matcher_opts = [
      institution_id: bank_account.institution_id,
      external_counterparty_only?: true,
      connected_account_iban: connected_account_iban
    ]

    Enum.map(transactions, fn transaction ->
      candidates =
        Map.get(candidate_map, transaction_match_key(transaction, connected_account_iban), [])

      case DuplicateTransactionMatcher.unique_match(
             transaction,
             candidates,
             matcher_opts
           ) do
        nil ->
          transaction

        matched_transaction ->
          Logger.info(
            "Deduplicating GoCardless transaction #{inspect(transaction[:internal_transaction_id])} " <>
              "against existing transaction #{matched_transaction.id} for bank account #{bank_account.id}"
          )

          transaction
          |> Map.put(:internal_transaction_id, matched_transaction.internal_transaction_id)
          |> Map.put(
            :transaction_id,
            matched_transaction.transaction_id || transaction[:transaction_id]
          )
      end
    end)
  end

  defp dedupe_final_upsert_batch(transactions, bank_account) do
    {deduped_transactions, _seen_keys, duplicate_count} =
      Enum.reduce(transactions, {[], MapSet.new(), 0}, fn transaction, {kept, seen_keys, dropped} ->
        key = final_upsert_key(transaction, bank_account.organization_id)

        if MapSet.member?(seen_keys, key) do
          {kept, seen_keys, dropped + 1}
        else
          {[transaction | kept], MapSet.put(seen_keys, key), dropped}
        end
      end)

    if duplicate_count > 0 do
      Logger.warning(
        "Dropped #{duplicate_count} duplicate transactions from sync batch for bank account #{bank_account.id}"
      )
    end

    Enum.reverse(deduped_transactions)
  end

  defp final_upsert_key(transaction, organization_id) do
    {
      Map.get(transaction, :internal_transaction_id),
      Map.get(transaction, :bank_account_id),
      organization_id
    }
  end

  defp load_existing_transactions_for_dedupe(bank_account, transactions, scope) do
    {oldest_date, newest_date} = replay_date_bounds(transactions)

    Transaction
    |> Ash.Query.filter(expr(bank_account_id == ^bank_account.id))
    |> apply_replay_date_filter(oldest_date, newest_date)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(scope: scope)
  end

  defp apply_replay_date_filter(query, nil, nil), do: query

  defp apply_replay_date_filter(query, oldest_date, newest_date) do
    lower_bound = Date.add(oldest_date, -@sync_candidate_date_tolerance_days)
    upper_bound = Date.add(newest_date, @sync_candidate_date_tolerance_days)

    Ash.Query.filter(
      query,
      expr(
        (is_nil(booking_date) and is_nil(value_date)) or
          (booking_date >= ^lower_bound and booking_date <= ^upper_bound) or
          (value_date >= ^lower_bound and value_date <= ^upper_bound)
      )
    )
  end

  defp build_candidate_transaction_buckets(transactions, connected_account_iban) do
    Enum.group_by(transactions, &transaction_match_key(&1, connected_account_iban))
  end

  defp transaction_match_key(transaction, connected_account_iban) do
    base_key = [
      transaction.amount |> Money.to_decimal() |> normalized_amount(),
      transaction.amount |> Money.to_currency_code() |> Atom.to_string() |> normalized_text()
    ]

    case TransactionDirection.direction(transaction, connected_account_iban) do
      :income ->
        base_key ++
          [
            normalized_text(Map.get(transaction, :debtor_name)),
            normalized_text(Map.get(transaction, :debtor_account))
          ]

      :expense ->
        base_key ++
          [
            normalized_text(Map.get(transaction, :creditor_name)),
            normalized_text(Map.get(transaction, :creditor_account))
          ]
    end
  end

  defp normalized_amount(value) do
    value
    |> Decimal.normalize()
    |> Decimal.to_string()
  end

  defp normalized_text(nil), do: ""

  defp normalized_text(value), do: value |> to_string() |> String.downcase() |> String.trim()

  defp replay_date_bounds(transactions) do
    dates =
      transactions
      |> Enum.map(&DuplicateTransactionMatcher.replay_reference_date/1)
      |> Enum.reject(&is_nil/1)

    case dates do
      [] -> {nil, nil}
      _ -> {Enum.min(dates), Enum.max(dates)}
    end
  end
end
