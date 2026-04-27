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
  alias Firmowid.Ash.Finances.DuplicateTransactionMatcher
  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.Ash.Finances.GoCardless.TransactionParser
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

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
          {:error, Ash.Changeset.add_error(changeset, "sync failed: #{inspect(reason)}")}
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
        expire_parent_requisition(bank_account, scope)
        {:error, :requisition_expired}

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
    case Requisition.expire(bank_account.requisition_id, scope: scope) do
      {:ok, _} ->
        Logger.info("Expired requisition #{bank_account.requisition_id} during sync")

      {:error, reason} ->
        Logger.warning("Could not expire requisition #{bank_account.requisition_id}: #{inspect(reason)}")
    end
  end

  defp upsert_transactions(booked_transactions, bank_account, previous_successful_sync_at, scope) do
    %{transactions: parsed_transactions, errors: parse_errors} =
      TransactionParser.parse_all(booked_transactions)

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
      Ash.bulk_create(
        transactions,
        Transaction,
        :upsert_from_sync,
        scope: scope,
        upsert?: true,
        return_errors?: true,
        stop_on_error?: false,
        batch_size: 100,
        notify?: true,
        actor: %SystemActor{org_id: bank_account.organization_id, role: :bank_sync}
      )

    case result do
      %{status: :success} ->
        Logger.debug("Synced transactions for bank account #{bank_account.id}")
        :ok

      %{status: :partial_success, errors: errors} ->
        Logger.warning(
          "Partial sync for bank account #{bank_account.id}: " <>
            "#{length(errors)} errors — #{inspect(Enum.take(errors, 3))}"
        )

        report_upsert_errors(errors, bank_account)
        :ok

      %{status: :error, errors: errors} ->
        Logger.error("Failed to sync transactions: #{inspect(Enum.take(errors, 3))}")
        report_upsert_errors(errors, bank_account)
        {:error, :upsert_failed}
    end
  end

  defp report_parse_errors([], _bank_account), do: :ok

  defp report_parse_errors(errors, bank_account) do
    Enum.each(errors, &report_parse_error(&1, bank_account))
  end

  defp report_parse_error(error, bank_account) do
    Logger.warning("Skipping GoCardless transaction for bank account #{bank_account.id}: #{Exception.message(error)}")

    Sentry.capture_exception(error,
      tags: %{
        source: "gocardless_transaction_sync",
        stage: "parse"
      },
      extra: %{
        bank_account_id: bank_account.id,
        organization_id: bank_account.organization_id,
        requisition_id: bank_account.requisition_id,
        transaction_id: Map.get(error, :transaction_id),
        internal_transaction_id: Map.get(error, :internal_transaction_id),
        raw_amount: inspect(Map.get(error, :raw_amount))
      }
    )
  rescue
    sentry_error ->
      Logger.warning("Failed to report transaction parse error to Sentry: #{Exception.message(sentry_error)}")
  end

  defp report_upsert_errors(errors, bank_account) do
    Logger.error("Transaction upsert errors for bank account #{bank_account.id}: #{inspect(Enum.take(errors, 3))}")

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
        errors: inspect(Enum.take(errors, 10))
      }
    )
  rescue
    sentry_error ->
      Logger.warning("Failed to report transaction upsert error to Sentry: #{Exception.message(sentry_error)}")
  end

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

    candidate_map = build_candidate_transaction_buckets(existing_transactions)

    matcher_opts = [institution_id: bank_account.institution_id]

    Enum.map(transactions, fn transaction ->
      candidates = Map.get(candidate_map, transaction_match_key(transaction), [])

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

  defp build_candidate_transaction_buckets(transactions) do
    Enum.group_by(transactions, &transaction_match_key/1)
  end

  defp transaction_match_key(transaction) do
    {
      normalized_amount(transaction),
      normalized_text(Map.get(transaction, :transaction_currency)),
      normalized_text(Map.get(transaction, :debtor_name)),
      normalized_text(Map.get(transaction, :debtor_account)),
      normalized_text(Map.get(transaction, :creditor_name)),
      normalized_text(Map.get(transaction, :creditor_account))
    }
  end

  defp normalized_amount(nil), do: nil

  defp normalized_amount(value) do
    case Decimal.cast(value) do
      {:ok, decimal} ->
        decimal
        |> Decimal.normalize()
        |> Decimal.to_string()

      :error ->
        nil
    end
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
