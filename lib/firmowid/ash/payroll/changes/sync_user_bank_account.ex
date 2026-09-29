defmodule Firmowid.Ash.Payroll.Changes.SyncUserBankAccount do
  @moduledoc """
  After creating an employment contract, syncs the employee bank account number
  extracted from the document onto the user profile.
  """

  use Ash.Resource.Change

  alias Firmowid.Ash.Core

  require Logger

  @impl true
  def change(changeset, _opts, context) do
    bank_account_number = Ash.Changeset.get_argument(changeset, :bank_account_number)

    Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
      with {:ok, contract} <- result,
           do: sync_bank_account(contract, bank_account_number, context)

      result
    end)
  end

  defp sync_bank_account(contract, extracted, context) do
    if blank?(extracted) do
      contract
    else
      write_bank_account(contract, extracted, context)
    end
  end

  defp write_bank_account(contract, bank_account_number, context) do
    opts = update_opts(context, contract)

    with {:ok, user} <- Core.get_user(contract.user_id, opts),
         {:ok, _user} <-
           Core.update_profile(user, %{bank_account_number: bank_account_number}, opts) do
      contract
    else
      {:error, reason} ->
        Logger.warning(
          "Skipped bank account from employment contract " <>
            "contract_id=#{contract.id} value=#{inspect(bank_account_number)} " <>
            "reason=#{inspect(reason)}"
        )

        contract
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true

  defp update_opts(context, contract) do
    context
    |> Ash.Context.to_opts()
    |> Keyword.take([:actor, :tenant, :authorize?, :tracer])
    |> Keyword.put(:tenant, contract.organization_id)
  end
end
