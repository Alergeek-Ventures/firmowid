defmodule Firmowid.Ash.Finances.GoCardless.TransactionParserTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Finances.GoCardless.TransactionParser
  alias Firmowid.Ash.Finances.GoCardless.TransactionParser.InvalidTransactionAmountError

  describe "parse/1" do
    test "normalizes grouped negative amounts before sync" do
      assert {:ok, parsed} =
               TransactionParser.parse(
                 sample_transaction(%{
                   "transactionAmount" => %{"amount" => "-29,247.00", "currency" => "PLN"}
                 })
               )

      assert Money.to_decimal(parsed.amount) == Decimal.new("-29247.00")
      assert parsed.amount |> Money.to_currency_code() |> Atom.to_string() == "PLN"
      assert parsed.transaction_id == "tx-1"
      assert parsed.internal_transaction_id == "int-1"
    end

    test "keeps already canonical amounts unchanged" do
      assert {:ok, parsed} =
               TransactionParser.parse(
                 sample_transaction(%{
                   "transactionAmount" => %{"amount" => "-29247.00", "currency" => "PLN"}
                 })
               )

      assert Money.to_decimal(parsed.amount) == Decimal.new("-29247.00")
    end
  end

  describe "parse_all/1" do
    test "skips invalid amount formats and returns structured errors" do
      result =
        TransactionParser.parse_all([
          sample_transaction(%{"transactionId" => "tx-valid"}),
          sample_transaction(%{
            "transactionId" => "tx-invalid",
            "internalTransactionId" => "int-invalid",
            "transactionAmount" => %{"amount" => "29.247,00", "currency" => "PLN"}
          })
        ])

      assert [%{transaction_id: "tx-valid"} = parsed_transaction] = result.transactions
      assert Money.to_decimal(parsed_transaction.amount) == Decimal.new("-120.00")
      assert parsed_transaction.amount |> Money.to_currency_code() |> Atom.to_string() == "PLN"

      assert [error] = result.errors
      assert %InvalidTransactionAmountError{} = error
      assert error.transaction_id == "tx-invalid"
      assert error.internal_transaction_id == "int-invalid"
      assert error.raw_amount == "29.247,00"
    end
  end

  defp sample_transaction(overrides) do
    Map.merge(
      %{
        "transactionId" => "tx-1",
        "internalTransactionId" => "int-1",
        "debtorName" => "Debtor",
        "debtorAccount" => %{"iban" => "PL10101010101010101010101010"},
        "creditorName" => "Creditor",
        "creditorAccount" => %{"iban" => "PL20202020202020202020202020"},
        "transactionAmount" => %{"amount" => "-120.00", "currency" => "PLN"},
        "bookingDate" => "2026-04-21",
        "valueDate" => "2026-04-21",
        "remittanceInformationUnstructured" => "Invoice payment"
      },
      overrides
    )
  end
end
