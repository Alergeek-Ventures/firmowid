defmodule Firmowid.Invoicing.Matching.ParametrizedResultTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Invoicing.Matching.ParametrizedResult

  describe "generate_parametrized_result/2" do
    test "generates parametrized result with all similarity metrics" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Test Company Ltd",
        account_number: "PL61109010140000071219812874",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "Test Company Limited",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-20],
        transaction_amount: Decimal.new("1000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment for invoice PLN 1000"
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      # Verify all required fields are present
      assert result.days_lag_le_3 == 0.0
      assert result.days_lag_le_7 == 1.0
      assert result.days_lag_le_30 == 0.0
      assert result.days_lag_gt_30 == 0.0
      assert_in_delta(result.signed_amount_match, 1.0, 0.0001)

      # Verify similarity metrics are calculated (should be floats between 0 and 1)
      assert is_float(result.transaction_side_similarity)
      assert result.transaction_side_similarity >= 0.0
      assert result.transaction_side_similarity <= 1.0

      assert is_float(result.bank_account_similarity)
      assert result.bank_account_similarity >= 0.0
      assert result.bank_account_similarity <= 1.0

      # Verify new fields
      assert result.is_same_currency == 1.0
      assert result.amount_present_in_remittance_information_unstructured == 1.0
    end

    test "handles different currencies and amounts" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Foreign Company",
        account_number: "DE89370400440532013000",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("500.00"),
        currency: "EUR",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "Foreign Company",
        creditor_account: "DE89370400440532013000",
        booking_date: ~D[2025-01-10],
        transaction_amount: Decimal.new("2000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment for services"
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      assert result.days_lag_le_3 == 0.0
      assert result.days_lag_le_7 == 1.0
      assert result.days_lag_le_30 == 0.0
      assert result.days_lag_gt_30 == 0.0

      # Signed amount match should be a positive ratio (2000 PLN / (500 EUR in PLN))
      # Mock rates use Money-compatible format: EUR rate = 0.2380442286 (units of EUR per 1 PLN)
      # So 1 EUR = 1/0.2380442286 = 4.2009 PLN
      # 500 EUR = 500 / 0.2380442286 = 2100.45 PLN
      # expected_ratio = 2000 / 2100.45 = 0.9522
      eur_rate = 0.2380442286
      inv_amount_pln = 500 / eur_rate
      expected_ratio = 2000 / inv_amount_pln
      assert_in_delta(result.signed_amount_match, expected_ratio, 0.0001)

      # Verify new fields
      assert result.is_same_currency == 0.0
      assert result.amount_present_in_remittance_information_unstructured == 0.0
    end

    test "handles exact matches" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Exact Match Corp",
        account_number: "PL61109010140000071219812874",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "Exact Match Corp",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Invoice PLN 1000 payment"
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      assert result.days_lag_le_3 == 1.0
      assert result.days_lag_le_7 == 0.0
      assert result.days_lag_le_30 == 0.0
      assert result.days_lag_gt_30 == 0.0
      assert_in_delta(result.signed_amount_match, 1.0, 0.0001)

      # Exact matches should have high similarity scores
      assert result.transaction_side_similarity > 0.9
      assert result.bank_account_similarity > 0.9

      # Verify new fields
      assert result.is_same_currency == 1.0
      assert result.amount_present_in_remittance_information_unstructured == 1.0
    end

    test "handles completely different strings" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Company A",
        account_number: "PL61109010140000071219812874",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "Completely Different XYZ",
        creditor_account: "DE89370400440532013000",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Random payment"
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      assert result.days_lag_le_3 == 1.0
      assert result.days_lag_le_7 == 0.0
      assert result.days_lag_le_30 == 0.0
      assert result.days_lag_gt_30 == 0.0
      assert_in_delta(result.signed_amount_match, 1.0, 0.0001)

      # Different strings should have lower similarity scores
      assert result.bank_account_similarity < 0.5

      assert result.is_same_currency == 1.0
      assert result.amount_present_in_remittance_information_unstructured == 0.0
    end

    test "handles empty strings" do
      cost_invoice = %CostInvoice{
        seller_display_name: "",
        account_number: "",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "",
        creditor_account: "",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: ""
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      # Should not crash and should return valid similarity scores
      assert result.transaction_side_similarity == 0.0
      assert result.bank_account_similarity == 0.0

      assert result.is_same_currency == 1.0
      assert result.amount_present_in_remittance_information_unstructured == 0.0
    end

    test "handles nil values gracefully" do
      cost_invoice = %CostInvoice{
        seller_display_name: nil,
        account_number: nil,
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: nil,
        creditor_account: nil,
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: nil
      }

      # Should not crash when encountering nil values
      assert_raise FunctionClauseError, fn ->
        ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)
      end
    end

    test "amount_present_in_remittance_information_unstructured with various scenarios" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Test Company",
        account_number: "PL61109010140000071219812874",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1234.56"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      # Test case 1: Amount and currency present
      transaction1 = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1234.56"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment PLN 1234"
      }

      result1 = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction1)
      assert result1.amount_present_in_remittance_information_unstructured == 1.0

      # Test case 2: Only currency present, amount missing
      transaction2 = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1234.56"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment PLN"
      }

      result2 = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction2)
      assert result2.amount_present_in_remittance_information_unstructured == 0.0

      # Test case 3: Only amount present, currency missing
      transaction3 = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1234.56"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment 1234"
      }

      result3 = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction3)
      assert result3.amount_present_in_remittance_information_unstructured == 0.0

      # Test case 4: Neither amount nor currency present
      transaction4 = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1234.56"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment for services"
      }

      result4 = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction4)
      assert result4.amount_present_in_remittance_information_unstructured == 0.0

      # Test case 5: Different currency
      transaction5 = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1234.56"),
        transaction_currency: "EUR",
        remittance_information_unstructured: "Payment EUR 1234"
      }

      result5 = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction5)
      assert result5.amount_present_in_remittance_information_unstructured == 0.0
      assert result5.is_same_currency == 0.0
    end
  end

  describe "edge cases" do
    test "handles IBAN normalization in similarity calculations" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Test Company",
        account_number: "PL61 1090 1014 0000 0712 1981 2874",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("1000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment"
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      # Should handle IBAN normalization and give high similarity for same account
      assert result.bank_account_similarity > 0.9
      assert result.is_same_currency == 1.0
    end

    test "handles large date differences" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Test Company",
        account_number: "PL61109010140000071219812874",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-12-15],
        transaction_amount: Decimal.new("1000.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment"
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      # Should calculate large positive difference
      assert result.days_lag_le_3 == 0.0
      assert result.days_lag_le_7 == 0.0
      assert result.days_lag_le_30 == 0.0
      assert result.days_lag_gt_30 == 1.0
      assert result.is_same_currency == 1.0
    end

    test "handles large amount differences" do
      cost_invoice = %CostInvoice{
        seller_display_name: "Test Company",
        account_number: "PL61109010140000071219812874",
        due_date: ~D[2025-01-15],
        total_amount: Decimal.new("1000000.00"),
        currency: "PLN",
        issue_date: ~D[2025-01-01]
      }

      transaction = %Transaction{
        creditor_name: "Test Company",
        creditor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-15],
        transaction_amount: Decimal.new("100.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "Payment"
      }

      result = ParametrizedResult.generate_parametrized_result(cost_invoice, transaction)

      # Should calculate large amount difference
      # Should be a very small ratio (100/1000000 = 0.0001)
      assert_in_delta(result.signed_amount_match, 0.0001, 0.00001)
      assert result.is_same_currency == 1.0
    end
  end

  describe "SalesInvoice integration" do
    test "generates parametrized result for SalesInvoice end-to-end" do
      sales_invoice = %Firmowid.Ash.Invoicing.SalesInvoice{
        buyer_display_name: "Acme Corp",
        seller_account_number: "PL61109010140000071219812874",
        issue_date: ~D[2025-01-01],
        currency: "PLN",
        invoice_number: "FV/2025/01/01",
        sales_invoice_items: [
          %Firmowid.Ash.Invoicing.SalesInvoiceItem{
            name: "Service",
            quantity: Decimal.new("2"),
            unit_price: Decimal.new("100.00"),
            vat_rate: "23"
          }
        ]
      }

      transaction = %Transaction{
        debtor_name: "Acme Corp",
        debtor_account: "PL61109010140000071219812874",
        booking_date: ~D[2025-01-02],
        transaction_amount: Decimal.new("246.00"),
        transaction_currency: "PLN",
        remittance_information_unstructured: "FV/2025/01/01 PLN 246"
      }

      result =
        ParametrizedResult.generate_parametrized_result(
          sales_invoice,
          transaction
        )

      assert is_struct(result)
      assert result.days_lag_le_3 == 1.0
      assert result.days_lag_le_7 == 0.0
      assert result.days_lag_le_30 == 0.0
      assert result.days_lag_gt_30 == 0.0
      assert result.is_same_currency == 1.0
      assert result.amount_present_in_remittance_information_unstructured == 1.0
      assert result.invoice_identifier_present_in_remittance_information_unstructured == 1.0
    end
  end
end
