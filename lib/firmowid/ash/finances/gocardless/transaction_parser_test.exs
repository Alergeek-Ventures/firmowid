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

    test "normalizes a Revolut EXCHANGE and completes the own side" do
      transaction =
        sample_transaction(%{
          "proprietaryBankTransactionCode" => "exchange",
          "debtorName" => nil,
          "debtorAccount" => nil,
          "creditorName" => nil,
          "creditorAccount" => nil,
          "remittanceInformationUnstructured" => nil,
          "remittanceInformationUnstructuredArray" => ["EUR", "PLN"],
          "currencyExchange" => %{
            "sourceCurrency" => "EUR",
            "targetCurrency" => "PLN",
            "exchangeRate" => "4.305..."
          },
          "transactionAmount" => %{"amount" => "10.00", "currency" => "PLN"}
        })

      assert {:ok, parsed} =
               TransactionParser.parse(transaction, %{
                 "institution_id" => "REVOLUT_REVOGB21",
                 "institution_name" => "Revolut",
                 "owner_name" => "My Company",
                 "iban" => "PL40404040404040404040404040"
               })

      assert parsed.debtor_name == "Revolut"
      assert parsed.creditor_name == "My Company"
      assert parsed.creditor_account == "PL40404040404040404040404040"

      assert parsed.remittance_information_unstructured ==
               "EUR | PLN · EUR → PLN · kurs 4.305..."
    end

    test "normalizes a Revolut CHARGE onto the creditor side" do
      transaction =
        sample_transaction(%{
          "proprietaryBankTransactionCode" => "ChArGe",
          "debtorName" => nil,
          "debtorAccount" => nil,
          "creditorName" => nil,
          "creditorAccount" => nil,
          "remittanceInformationUnstructured" => nil,
          "remittanceInformationUnstructuredArray" => nil,
          "transactionAmount" => %{"amount" => "-2.00", "currency" => "PLN"}
        })

      assert {:ok, parsed} =
               TransactionParser.parse(transaction, %{
                 institution_id: "REVOLUT_REVOGB21",
                 institution_name: "Revolut",
                 owner_name: "My Company",
                 iban: "PL40404040404040404040404040"
               })

      assert parsed.creditor_name == "Revolut"
      assert parsed.debtor_name == "My Company"
      assert parsed.remittance_information_unstructured == "Opłata Revolut"
    end

    test "preserves a Revolut TOPUP debtor and joined description" do
      transaction =
        sample_transaction(%{
          "proprietaryBankTransactionCode" => "TOPUP",
          "debtorName" => "Provider debtor",
          "debtorAccount" => %{"iban" => "PL30303030303030303030303030"},
          "creditorName" => nil,
          "creditorAccount" => nil,
          "remittanceInformationUnstructured" => nil,
          "remittanceInformationUnstructuredArray" => ["Top up", "salary"],
          "transactionAmount" => %{"amount" => "20.00", "currency" => "EUR"}
        })

      assert {:ok, parsed} =
               TransactionParser.parse(transaction, %{
                 institution_id: "REVOLUT_REVOGB21",
                 institution_name: "Revolut",
                 owner_name: "My Company",
                 iban: "PL40404040404040404040404040"
               })

      assert parsed.debtor_name == "Provider debtor"
      assert parsed.remittance_information_unstructured == "Top up | salary"
      assert parsed.creditor_name == "My Company"
    end

    test "leaves the same code generic for a non-Revolut account" do
      transaction =
        sample_transaction(%{
          "proprietaryBankTransactionCode" => "CHARGE",
          "debtorName" => nil,
          "debtorAccount" => nil,
          "creditorName" => nil,
          "creditorAccount" => nil,
          "remittanceInformationUnstructured" => nil,
          "remittanceInformationUnstructuredArray" => nil
        })

      assert {:ok, parsed} =
               TransactionParser.parse(transaction, %{institution_id: "OTHER_BANK"})

      assert parsed.creditor_name == nil
      assert parsed.debtor_name == nil
      assert parsed.remittance_information_unstructured == nil
    end

    test "fills only the signed own side for no-party EXCHANGE rows" do
      account = %{owner_name: "My Company", iban: "PL40404040404040404040404040"}

      negative_transaction =
        sample_transaction(%{
          "proprietaryBankTransactionCode" => "EXCHANGE",
          "debtorName" => nil,
          "debtorAccount" => nil,
          "creditorName" => nil,
          "creditorAccount" => nil,
          "remittanceInformationUnstructured" => nil,
          "remittanceInformationUnstructuredArray" => ["Exchange", "EUR to PLN"]
        })

      positive_transaction =
        Map.put(negative_transaction, "transactionAmount", %{
          "amount" => "10.00",
          "currency" => "PLN"
        })

      assert {:ok, negative} = TransactionParser.parse(negative_transaction, account)
      assert {:ok, positive} = TransactionParser.parse(positive_transaction, account)

      assert negative.remittance_information_unstructured == "Exchange | EUR to PLN"
      assert positive.remittance_information_unstructured == "Exchange | EUR to PLN"

      assert {negative.debtor_name, negative.debtor_account} ==
               {"My Company", "PL40404040404040404040404040"}

      assert {negative.creditor_name, negative.creditor_account} == {nil, nil}

      assert {positive.creditor_name, positive.creditor_account} ==
               {"My Company", "PL40404040404040404040404040"}

      assert {positive.debtor_name, positive.debtor_account} == {nil, nil}
    end

    test "fills neither side for a zero transaction" do
      transaction =
        sample_transaction(%{
          "debtorName" => nil,
          "debtorAccount" => nil,
          "creditorName" => nil,
          "creditorAccount" => nil,
          "transactionAmount" => %{"amount" => "0.00", "currency" => "PLN"}
        })

      assert {:ok, parsed} =
               TransactionParser.parse(transaction, %{owner_name: "My Company", iban: "PL4040"})

      assert parsed.debtor_name == nil
      assert parsed.debtor_account == nil
      assert parsed.creditor_name == nil
      assert parsed.creditor_account == nil
    end

    test "preserves provider party values and scalar description" do
      transaction =
        sample_transaction(%{
          "remittanceInformationUnstructuredArray" => ["Other description"],
          "creditorName" => "Provider creditor",
          "creditorAccount" => %{"iban" => "PL50505050505050505050505050"}
        })

      assert {:ok, parsed} =
               TransactionParser.parse(transaction, %{
                 owner_name: "My Company",
                 iban: "PL40404040404040404040404040"
               })

      assert parsed.remittance_information_unstructured == "Invoice payment"
      assert parsed.creditor_name == "Provider creditor"
      assert parsed.creditor_account == "PL50505050505050505050505050"
    end

    test "does not combine contradictory own-side values, but trusts a matching own IBAN" do
      account = %{owner_name: "My Company", iban: "pl40 4040 4040 4040 4040 4040 4040"}

      contradictory =
        sample_transaction(%{
          "debtorName" => "Other Company",
          "debtorAccount" => nil,
          "transactionAmount" => %{"amount" => "-12.00", "currency" => "PLN"}
        })

      assert {:ok, parsed} = TransactionParser.parse(contradictory, account)
      assert parsed.debtor_name == "Other Company"
      assert parsed.debtor_account == nil

      matching_iban =
        sample_transaction(%{
          "debtorName" => nil,
          "debtorAccount" => %{"iban" => "PL40404040404040404040404040"},
          "transactionAmount" => %{"amount" => "-12.00", "currency" => "PLN"}
        })

      assert {:ok, parsed} = TransactionParser.parse(matching_iban, account)

      assert {parsed.debtor_name, parsed.debtor_account} == {nil, "PL40404040404040404040404040"}
    end

    test "does not complete the signed side when the opposite side has the connected IBAN" do
      account = %{owner_name: "My Company", iban: "PL40404040404040404040404040"}

      for amount <- ["12.00", "-12.00"] do
        {debtor_account, creditor_account} =
          if amount == "12.00", do: {account.iban, nil}, else: {nil, account.iban}

        transaction =
          sample_transaction(%{
            "debtorName" => nil,
            "debtorAccount" => debtor_account && %{"iban" => debtor_account},
            "creditorName" => nil,
            "creditorAccount" => creditor_account && %{"iban" => creditor_account},
            "transactionAmount" => %{"amount" => amount, "currency" => "PLN"}
          })

        assert {:ok, parsed} = TransactionParser.parse(transaction, account)

        if amount == "12.00" do
          assert {parsed.creditor_name, parsed.creditor_account} == {nil, nil}
          assert parsed.debtor_account == account.iban
        else
          assert {parsed.debtor_name, parsed.debtor_account} == {nil, nil}
          assert parsed.creditor_account == account.iban
        end
      end
    end

    test "falls back to additional and structured information, but not proprietary code" do
      base = sample_transaction(%{"remittanceInformationUnstructured" => nil})

      assert {:ok, parsed} =
               TransactionParser.parse(Map.put(base, "additionalInformation", "Additional details"))

      assert parsed.remittance_information_unstructured == "Additional details"

      assert {:ok, parsed} =
               TransactionParser.parse(
                 Map.merge(base, %{
                   "additionalInformation" => nil,
                   "additionalInformationStructured" => %{"reference" => "Structured details"}
                 })
               )

      assert parsed.remittance_information_unstructured == "Structured details"

      assert {:ok, parsed} =
               TransactionParser.parse(
                 Map.merge(base, %{
                   "additionalInformation" => nil,
                   "additionalInformationStructured" => nil,
                   "proprietaryBankTransactionCode" => "SEPA"
                 })
               )

      assert parsed.remittance_information_unstructured == nil
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
