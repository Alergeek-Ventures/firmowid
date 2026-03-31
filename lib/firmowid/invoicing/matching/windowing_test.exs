defmodule Firmowid.Invoicing.Matching.WindowingTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.Matching.Windowing
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  describe "pre_filter_invoice_transactions/2" do
    setup do
      cost_invoice = %CostInvoice{
        total_amount: Decimal.new("100.0"),
        currency: "PLN",
        issue_date: ~D[2025-01-15],
        sale_date: ~D[2025-01-15],
        due_date: ~D[2025-02-15],
        invoice_identifier: "1234567890",
        description: "Test invoice"
      }

      cost_invoice_eur = %CostInvoice{
        total_amount: Decimal.new("100.0"),
        currency: "EUR",
        issue_date: ~D[2025-01-15],
        sale_date: ~D[2025-01-15],
        due_date: ~D[2025-02-15],
        invoice_identifier: "1234567890",
        description: "Test invoice EUR"
      }

      transactions = [
        %Transaction{
          transaction_amount: Decimal.new("-95.0"),
          transaction_currency: "PLN",
          booking_date: ~D[2025-01-14]
        },
        %Transaction{
          transaction_amount: Decimal.new("-110.0"),
          transaction_currency: "PLN",
          booking_date: ~D[2025-03-20]
        },
        %Transaction{
          # changed from -105.0 to -120.0 (outside amount window)
          transaction_amount: Decimal.new("-120.0"),
          transaction_currency: "PLN",
          booking_date: ~D[2025-02-10]
        },
        %Transaction{
          transaction_amount: Decimal.new("-85.0"),
          transaction_currency: "PLN",
          booking_date: ~D[2025-02-10]
        },
        %Transaction{
          transaction_amount: Decimal.new("-85.0"),
          transaction_currency: "PLN",
          booking_date: ~D[2026-02-10]
        },
        %Transaction{
          transaction_amount: Decimal.new("-95.0"),
          transaction_currency: "EUR",
          booking_date: ~D[2025-01-14]
        }
      ]

      %{
        cost_invoice: cost_invoice,
        cost_invoice_eur: cost_invoice_eur,
        transactions: transactions
      }
    end

    test "filters transactions outside time window and amount window for PLN", %{
      cost_invoice: cost_invoice,
      transactions: transactions
    } do
      result = Windowing.pre_filter_invoice_transactions(cost_invoice, transactions)
      # Only PLN transactions in the right time and amount window
      assert Enum.all?(result, &(&1.transaction_currency == "PLN"))
      assert Enum.all?(result, &(Decimal.cmp(&1.transaction_amount, 0) == :lt))
      assert length(result) == 2
    end

    test "filters transactions for non-PLN currency (EUR)", %{
      cost_invoice_eur: cost_invoice_eur,
      transactions: transactions
    } do
      result = Windowing.pre_filter_invoice_transactions(cost_invoice_eur, transactions)
      # Only EUR transactions in the right time and amount window
      assert Enum.any?(result, &(&1.transaction_currency == "EUR"))
    end

    test "filters transactions for SalesInvoice" do
      sales_invoice = %SalesInvoice{
        issue_date: ~D[2025-01-01],
        due_date: ~D[2025-01-31],
        currency: "PLN",
        sales_invoice_items: [
          %SalesInvoiceItem{
            quantity: 1,
            unit_price: Decimal.new("10.0"),
            vat_rate: "23"
          }
        ]
      }

      transactions = [
        %Transaction{
          booking_date: ~D[2023-01-15],
          transaction_amount: Decimal.new("10.0"),
          transaction_currency: "PLN"
        },
        %Transaction{
          booking_date: ~D[2024-12-01],
          transaction_amount: Decimal.new("10.0"),
          transaction_currency: "PLN"
        },
        %Transaction{
          booking_date: ~D[2025-01-15],
          transaction_amount: Decimal.new("12.3"),
          transaction_currency: "PLN"
        },
        %Transaction{
          booking_date: ~D[2025-03-15],
          transaction_amount: Decimal.new("10.0"),
          transaction_currency: "PLN"
        },
        %Transaction{
          booking_date: ~D[2027-01-15],
          transaction_amount: Decimal.new("10.0"),
          transaction_currency: "PLN"
        }
      ]

      result =
        Windowing.pre_filter_invoice_transactions(
          sales_invoice,
          transactions
        )

      assert length(result) == 1
      assert Enum.all?(result, &(&1.transaction_amount == Decimal.new("12.3")))
      assert Enum.all?(result, &(&1.transaction_currency == "PLN"))
    end
  end
end
