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

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, bank_account ->
      perform_sync(bank_account)
    end)
  end

  defp perform_sync(bank_account) do
    with {:ok, booked} <- fetch_transactions(bank_account),
         :ok <- upsert_transactions(booked, bank_account) do
      {:ok, bank_account}
    else
      {:error, :expired_eua} ->
        expire_parent_requisition(bank_account)
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

  defp expire_parent_requisition(bank_account) do
    case Requisition.expire(bank_account.requisition_id,
           tenant: bank_account.organization_id,
           authorize?: false,
           actor: %{}
         ) do
      {:ok, _} ->
        Logger.info("Expired requisition #{bank_account.requisition_id} during sync")

      {:error, reason} ->
        Logger.warning("Could not expire requisition #{bank_account.requisition_id}: #{inspect(reason)}")
    end
  end

  defp upsert_transactions(booked_transactions, bank_account) do
    transactions =
      booked_transactions
      |> TransactionParser.parse_all()
      |> Enum.map(&Map.put(&1, :bank_account_id, bank_account.id))

    result =
      Ash.bulk_create(
        transactions,
        Transaction,
        :upsert_from_sync,
        tenant: bank_account.organization_id,
        authorize?: false,
        upsert?: true,
        return_errors?: true,
        stop_on_error?: false,
        batch_size: 100,
        notify?: true
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

        :ok

      %{status: :error, errors: errors} ->
        Logger.error("Failed to sync transactions: #{inspect(Enum.take(errors, 3))}")
        {:error, :upsert_failed}
    end
  end
end
