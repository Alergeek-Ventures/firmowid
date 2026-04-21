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

  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.Ash.Finances.GoCardless.TransactionParser
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, bank_account ->
      case perform_sync(bank_account, build_sync_scope(bank_account)) do
        {:ok, _} ->
          {:ok, bank_account}

        {:error, reason} ->
          {:error, Ash.Changeset.add_error(changeset, "sync failed: #{inspect(reason)}")}
      end
    end)
  end

  defp perform_sync(bank_account, scope) do
    with {:ok, booked} <- fetch_transactions(bank_account),
         :ok <- upsert_transactions(booked, bank_account, scope) do
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

  defp upsert_transactions(booked_transactions, bank_account, scope) do
    %{transactions: parsed_transactions, errors: parse_errors} =
      TransactionParser.parse_all(booked_transactions)

    report_parse_errors(parse_errors, bank_account)

    transactions = Enum.map(parsed_transactions, &Map.put(&1, :bank_account_id, bank_account.id))

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
end
