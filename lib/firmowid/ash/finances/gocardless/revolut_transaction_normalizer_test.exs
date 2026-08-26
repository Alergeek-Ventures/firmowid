defmodule Firmowid.Ash.Finances.GoCardless.RevolutTransactionNormalizerTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Finances.GoCardless.RevolutTransactionNormalizer

  describe "normalize/2 EXCHANGE" do
    test "accepts a currency exchange map and normalizes its summary components" do
      data = %{
        "proprietary_bank_transaction_code" => "exchange",
        "amount" => Money.new!("PLN", "10.00"),
        "currency_exchange" => %{
          "source_currency" => " eur ",
          "target_currency" => " pln ",
          "exchange_rate" => " 4.305 "
        },
        "remittance_information_unstructured" => "Wymiana walut"
      }

      normalized = RevolutTransactionNormalizer.normalize(data, %{institution_name: nil})

      assert normalized["remittance_information_unstructured"] ==
               "Wymiana walut · EUR → PLN · kurs 4.305"

      assert normalized["debtor_name"] == "Revolut"
    end

    test "uses the first exchange map in a list and does not duplicate its suffix" do
      data = %{
        "proprietary_bank_transaction_code" => "EXCHANGE",
        "amount" => Money.new!("PLN", "10.00"),
        "currency_exchange" => [
          %{"source_currency" => " eur ", "target_currency" => " pln ", "exchange_rate" => 4.305},
          %{"source_currency" => "USD", "target_currency" => "PLN", "exchange_rate" => "4"}
        ],
        "remittance_information_unstructured" => "Wymiana walut · EUR → PLN · kurs 4.305"
      }

      normalized = RevolutTransactionNormalizer.normalize(data, %{institution_name: "Revolut"})

      assert normalized["remittance_information_unstructured"] ==
               "Wymiana walut · EUR → PLN · kurs 4.305"
    end

    test "uses the connected debtor account for a contradictory positive sign" do
      data = %{
        "proprietary_bank_transaction_code" => "EXCHANGE",
        "amount" => Money.new!("PLN", "10.00"),
        "debtor_account" => "PL123",
        "debtor_name" => "Existing account name",
        "creditor_account" => "PL456",
        "creditor_name" => nil,
        "remittance_information_unstructured" => "Wymiana walut"
      }

      normalized =
        RevolutTransactionNormalizer.normalize(data, %{
          iban: "PL123",
          institution_name: "Revolut"
        })

      assert normalized["creditor_name"] == "Revolut"
      assert normalized["debtor_name"] == "Existing account name"
    end
  end
end
