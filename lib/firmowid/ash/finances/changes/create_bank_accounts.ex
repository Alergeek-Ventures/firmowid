defmodule Firmowid.Ash.Finances.Changes.CreateBankAccounts do
  @moduledoc """
  After-action change that creates BankAccount records from GoCardless data.

  Called by the :accept action. Enqueues sync triggers for each created account.
  Failures are logged but don't fail the changeset - the requisition is already
  accepted, and bank accounts can be created on next sync.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Finances.GoCardless.ApiClient

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      case create_accounts(record) do
        {:ok, accounts} ->
          Enum.each(accounts, &enqueue_sync/1)
          {:ok, record}

        {:error, reason} ->
          Logger.warning("Failed to create bank accounts for requisition #{record.id}: #{inspect(reason)}")

          {:ok, record}
      end
    end)
  end

  defp create_accounts(record) do
    with {:ok, accounts} <- ApiClient.get_accounts_for_requisition(record.id) do
      bank_accounts =
        Enum.map(accounts, fn account ->
          BankAccount
          |> Ash.Changeset.for_create(
            :sync_from_bank,
            account_params(account, record.id),
            tenant: record.organization_id,
            actor: %{}
          )
          |> Ash.create!(tenant: record.organization_id, authorize?: false, actor: %{})
        end)

      {:ok, bank_accounts}
    end
  end

  defp account_params(account, requisition_id) do
    %{
      iban: account["iban"],
      gocardless_id: account["id"],
      owner_name: account["ownerName"],
      institution_id: account["institution_id"],
      institution_name: nested_get(account, ["institution", "name"]),
      currency: account["currency"],
      name: account["name"],
      requisition_id: requisition_id
    }
  end

  defp nested_get(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key)
        nil -> nil
      end
    end)
  end

  defp enqueue_sync(account) do
    AshOban.run_trigger(account, :sync_transactions, tenant: account.organization_id)
  rescue
    error ->
      Logger.warning("Failed to enqueue sync for account #{account.id}: #{inspect(error)}")
  end
end
