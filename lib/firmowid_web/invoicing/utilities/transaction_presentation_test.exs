defmodule FirmowidWeb.Invoicing.Utilities.TransactionPresentationTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidWeb.Invoicing.Utilities.TransactionPresentation

  test "connected creditor account overrides a contradictory amount sign" do
    transaction = transaction(amount: Money.new!("PLN", -100), creditor_account: "pl 12 345")

    assert TransactionPresentation.income?(transaction)
  end

  test "connected debtor account yields expense" do
    transaction = transaction(amount: Money.new!("PLN", 100), debtor_account: "PL 12 345")

    refute TransactionPresentation.income?(transaction)
  end

  test "without an account match direction follows the signed amount" do
    unmatched = %{bank_account: %{iban: "PL00000", institution_name: "Bank Polski"}}

    assert TransactionPresentation.income?(
             transaction(amount: Money.new!("PLN", 100), bank_account: unmatched.bank_account)
           )

    refute TransactionPresentation.income?(
             transaction(amount: Money.new!("PLN", -100), bank_account: unmatched.bank_account)
           )
  end

  test "missing and historical N/A parties fall back to a generic counterparty" do
    assert TransactionPresentation.counterparty_name(transaction(debtor_name: "N/A", creditor_name: nil)) ==
             "Transakcja bankowa"
  end

  test "signed amount follows presentation direction despite the raw amount sign" do
    income = transaction(amount: Money.new!("PLN", -100), creditor_account: "PL 12 345")
    expense = transaction(amount: Money.new!("PLN", 100), debtor_account: "PL 12 345")

    assert TransactionPresentation.signed_amount(income) == Money.new!("PLN", 100)
    assert TransactionPresentation.signed_amount(expense) == Money.new!("PLN", -100)
  end

  test "not loaded bank account falls back to the generic counterparty" do
    transaction =
      transaction(bank_account: %Ash.NotLoaded{}, debtor_name: nil, creditor_name: nil)

    assert TransactionPresentation.counterparty_name(transaction) == "Transakcja bankowa"
  end

  test "not loaded bank account does not affect amount-based direction" do
    transaction = transaction(bank_account: %Ash.NotLoaded{}, amount: Money.new!("PLN", 100))

    assert TransactionPresentation.income?(transaction)
  end

  defp transaction(overrides) do
    Map.merge(
      %{
        amount: Money.new!("PLN", 0),
        creditor_account: "PL987654",
        debtor_account: "PL12345",
        creditor_name: "Creditor",
        debtor_name: "Debtor",
        bank_account: %{iban: "PL12345", institution_name: "Bank Polski"}
      },
      Map.new(overrides)
    )
  end
end
