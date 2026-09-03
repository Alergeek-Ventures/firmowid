defmodule Firmowid.Ash.Finances.Changes.CreateBankAccounts do
  @moduledoc """
  After-action change that creates BankAccount records from GoCardless data.

  Called by the :accept action. Enqueues sync triggers for each created account.
  Failures are logged but don't fail the changeset - the requisition is already
  accepted, and bank accounts can be created on next sync.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.ErrorKind

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
    ash_opts = Ash.Context.to_opts(context)

    with {:ok, accounts} <- ApiClient.get_accounts_for_requisition(record.id) do
      bank_accounts =
        Enum.map(accounts, fn account ->
          opts =
            ash_opts |> Keyword.delete(:tenant) |> Keyword.put(:tenant, record.organization_id)

          account
          |> account_params(record.id)
          |> Finances.changeset_to_sync_bank_account(opts)
          |> Ash.create!(opts)
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
