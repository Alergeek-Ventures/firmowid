defmodule Firmowid.Ash.Finances.TransactionDirectionTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Finances.TransactionDirection

  test "connected creditor takes precedence over amount sign" do
    transaction = transaction(amount: Money.new!("PLN", -100), creditor_account: "PL 123")

    assert TransactionDirection.direction(transaction) == :income
  end

  test "connected debtor takes precedence over amount sign" do
    transaction = transaction(amount: Money.new!("PLN", 100), debtor_account: "PL 123")

    assert TransactionDirection.direction(transaction, "PL123") == :expense
  end

  test "blank and N/A accounts fall back to the signed amount" do
    transaction =
      transaction(
        amount: Money.new!("PLN", 0),
        bank_account: %{iban: "N/A"},
        creditor_account: "N/A"
      )

    assert TransactionDirection.direction(transaction) == :expense
  end

  defp transaction(overrides) do
    Map.merge(
      %{
        amount: Money.new!("PLN", 0),
        creditor_account: "PL987",
        debtor_account: "PL123",
        bank_account: %{iban: "PL123"}
      },
      Map.new(overrides)
    )
  end
end
