defmodule Firmowid.Ash.Invoicing.Matching.WindowingTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.Matching.Windowing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem

  describe "pre_filter_invoice_transactions/2" do
    setup do
      cost_invoice = %CostInvoice{
        total_amount: Decimal.new("100.0"),
        currency: "PLN",
        effective_amount: Money.new!("PLN", Decimal.new("100.0")),
        issue_date: ~D[2025-01-15],
        sale_date: ~D[2025-01-15],
        due_date: ~D[2025-02-15],
        invoice_identifier: "1234567890",
        description: "Test invoice"
      }

      cost_invoice_eur = %CostInvoice{
        total_amount: Decimal.new("100.0"),
        currency: "EUR",
        effective_amount: Money.new!("EUR", Decimal.new("100.0")),
        issue_date: ~D[2025-01-15],
        sale_date: ~D[2025-01-15],
        due_date: ~D[2025-02-15],
        invoice_identifier: "1234567890",
        description: "Test invoice EUR"
      }

      transactions = [
        %Transaction{
          amount: Money.new!("PLN", Decimal.new("-95.0")),
          booking_date: ~D[2025-01-14]
        },
        %Transaction{
          amount: Money.new!("PLN", Decimal.new("-110.0")),
          booking_date: ~D[2025-03-20]
        },
        %Transaction{
          # changed from -105.0 to -120.0 (outside amount window)
          amount: Money.new!("PLN", Decimal.new("-120.0")),
          booking_date: ~D[2025-02-10]
        },
        %Transaction{
          amount: Money.new!("PLN", Decimal.new("-85.0")),
          booking_date: ~D[2025-02-10]
        },
        %Transaction{
          amount: Money.new!("PLN", Decimal.new("-85.0")),
          booking_date: ~D[2026-02-10]
        },
        %Transaction{
          amount: Money.new!("EUR", Decimal.new("-95.0")),
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
      assert Enum.all?(
               result,
               &(&1.amount |> Money.to_currency_code() |> Atom.to_string() == "PLN")
             )

      assert Enum.all?(result, &Money.negative?(&1.amount))
      assert length(result) == 2
    end

    test "filters transactions for non-PLN currency (EUR)", %{
      cost_invoice_eur: cost_invoice_eur,
      transactions: transactions
    } do
      result = Windowing.pre_filter_invoice_transactions(cost_invoice_eur, transactions)
      # Only EUR transactions in the right time and amount window
      assert Enum.any?(
               result,
               &(&1.amount |> Money.to_currency_code() |> Atom.to_string() == "EUR")
             )
    end

    test "filters transactions for SalesInvoice" do
      item =
        Ash.load!(
          %SalesInvoiceItem{
            quantity: Decimal.new("1"),
            unit_price: Decimal.new("10.0"),
            vat_rate: "23"
          },
          [:net_value, :vat_value, :gross_value],
          authorize?: false,
          actor: %{}
        )

      gross_value = Enum.reduce([item], Decimal.new(0), &Decimal.add(&2, &1.gross_value))

      sales_invoice = %SalesInvoice{
        issue_date: ~D[2025-01-01],
        due_date: ~D[2025-01-31],
        currency: "PLN",
        sales_invoice_items: [item],
        gross_value: gross_value,
        effective_amount: Money.new!("PLN", gross_value)
      }

      transactions = [
        %Transaction{
          booking_date: ~D[2023-01-15],
          amount: Money.new!("PLN", Decimal.new("10.0"))
        },
        %Transaction{
          booking_date: ~D[2024-12-01],
          amount: Money.new!("PLN", Decimal.new("10.0"))
        },
        %Transaction{
          booking_date: ~D[2025-01-15],
          amount: Money.new!("PLN", Decimal.new("12.3"))
        },
        %Transaction{
          booking_date: ~D[2025-03-15],
          amount: Money.new!("PLN", Decimal.new("10.0"))
        },
        %Transaction{
          booking_date: ~D[2027-01-15],
          amount: Money.new!("PLN", Decimal.new("10.0"))
        }
      ]

      result =
        Windowing.pre_filter_invoice_transactions(
          sales_invoice,
          transactions
        )

      assert length(result) == 1
      assert Enum.all?(result, &(Money.to_decimal(&1.amount) == Decimal.new("12.3")))

      assert Enum.all?(
               result,
               &(&1.amount |> Money.to_currency_code() |> Atom.to_string() == "PLN")
             )
    end
  end
end
