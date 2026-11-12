defmodule Firmowid.Finances.Changes.CreateBankAccounts do
  @moduledoc """
  After-action change that creates BankAccount records from GoCardless data.

  Called by the :accept action. Enqueues sync triggers for each created account.
  A GoCardless failure fails the action, so the requisition stays pending and
  the :check_status trigger retries the acceptance.
  """
  use Ash.Resource.Change

  alias Firmowid.Finances
  alias Firmowid.Finances.GoCardless.ApiClient

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      with {:ok, accounts} <- create_accounts(record, context) do
        Enum.each(
          accounts,
          &AshOban.run_trigger(&1, :sync_transactions, tenant: &1.organization_id)
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
end
