defmodule Firmowid.Ash.Finances.TransactionDirection do
  @moduledoc """
  Resolves whether a bank transaction is income or expense.

  When the connected bank account is known, account ownership takes precedence
  over the sign of the imported amount. A creditor match is income and a debtor
  match is expense. Transactions without a useful account match use the signed
  amount, where zero and negative amounts are expenses.
  """

  alias Firmowid.Ash.Finances.BankAccount

  @type direction :: :income | :expense
  @type transaction_like :: map() | struct()

  @doc """
  Returns a transaction direction using its loaded bank account IBAN.

  The account-aware overload is useful for transactions being synchronized
  before their bank account relationship is loaded.
  """
  @spec direction(transaction_like()) :: direction()
  @spec direction(transaction_like(), String.t() | nil) :: direction()
  def direction(transaction, connected_account_iban \\ nil) do
    connected_iban = connected_account_iban || bank_account_iban(transaction)

    cond do
      useful_account?(connected_iban) and
          same_account?(connected_iban, field(transaction, :creditor_account)) ->
        :income

      useful_account?(connected_iban) and
          same_account?(connected_iban, field(transaction, :debtor_account)) ->
        :expense

      Money.positive?(field(transaction, :amount)) ->
        :income

      true ->
        :expense
    end
  end

  defp bank_account_iban(transaction) do
    case field(transaction, :bank_account) do
      account when is_map(account) -> Map.get(account, :iban)
      _ -> nil
    end
  end

  defp same_account?(left, right), do: normalize_account(left) == normalize_account(right)

  defp useful_account?(value) when is_binary(value) do
    normalize_account(value) not in ["", "N/A"]
  end

  defp useful_account?(_value), do: false

  defp normalize_account(value), do: BankAccount.normalize_iban(value) || ""

  defp field(%_{} = struct, key), do: Map.get(struct, key)
  defp field(map, key) when is_map(map), do: Map.get(map, key)
end
