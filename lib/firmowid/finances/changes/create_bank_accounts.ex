defmodule Firmowid.Finances.Changes.CreateBankAccounts do
  @moduledoc """
  After-action change that creates BankAccount records from GoCardless data.

  Called by the :accept action. Enqueues sync triggers for each created account.
  Failures are logged but don't fail the changeset - the requisition is already
  accepted, and bank accounts can be created on next sync.
  """
  use Ash.Resource.Change

  alias Firmowid.ErrorKind
  alias Firmowid.Finances
  alias Firmowid.Finances.GoCardless.ApiClient

  require Logger

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      case create_accounts(record, context) do
        {:ok, accounts} ->
          Enum.each(accounts, &enqueue_sync/1)
          {:ok, record}

        {:error, reason} ->
          Logger.warning("Failed to create bank accounts for requisition",
            requisition_id: record.id,
            error_kind: ErrorKind.classify(reason)
          )

          {:ok, record}
      end
    end)
  end

  defp create_accounts(record, context) do
    opts = context |> Ash.Context.to_opts() |> Keyword.put(:tenant, record.organization_id)

    with {:ok, accounts} <- ApiClient.get_accounts_for_requisition(record.id) do
      {:ok, Enum.map(accounts, &Finances.sync_bank_account!(account_params(&1, record.id), opts))}
    end
  end

  defp account_params(account, requisition_id) do
    %{
      iban: account["iban"],
      gocardless_id: account["id"],
      owner_name: account["ownerName"],
      institution_id: account["institution_id"],
      institution_name: get_in(account, ["institution", "name"]),
      currency: account["currency"],
      name: account["name"],
      requisition_id: requisition_id
    }
  end

  defp enqueue_sync(account) do
    AshOban.run_trigger(account, :sync_transactions, tenant: account.organization_id)
  rescue
    error ->
      Logger.warning("Failed to enqueue sync for account",
        account_id: account.id,
        error_kind: ErrorKind.classify(error)
      )
  end
end
