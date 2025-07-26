defmodule Firmowid.Invoicing.Matching.Windowing do
  @moduledoc """
  This module is responsible for pre-filtering transactions, narrowing set of
  every transaction available to the ones relevant to the invoice.

  Pre-filtering is very broad and is only meant to be used as a first step
  in the matching process.
  """

  alias Firmowid.Currencies
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.Finances.Transaction

  @doc """
  Pre-filter the transactions list to only include ones
  that are sligthly within a time window and
  amount window. These windows are very generous.
  """
  @spec pre_filter_invoice_transactions(%CostInvoice{} | %SalesInvoice{}, [%Transaction{}]) :: [
          %Transaction{}
        ]
  def pre_filter_invoice_transactions(%CostInvoice{} = cost_invoice, transactions) do
    transactions
    |> Enum.filter(fn transaction ->
      within_time_window?(
        cost_invoice.issue_date,
        cost_invoice.due_date,
        transaction.booking_date
      ) and
        within_amount_window(cost_invoice, transaction)
    end)
  end

  def pre_filter_invoice_transactions(%SalesInvoice{} = sales_invoice, transactions) do
    transactions
    |> Enum.filter(fn transaction ->
      within_time_window?(
        sales_invoice.issue_date,
        sales_invoice.due_date,
        transaction.booking_date
      ) and
        within_amount_window(sales_invoice, transaction)
    end)
  end

  @spec within_time_window?(Date.t(), Date.t(), Date.t()) :: boolean()
  defp within_time_window?(issue_date, due_date, transaction_date) do
    # up to 10 days before it was issued
    past_cutoff = Timex.shift(issue_date, days: -10)
    # up to 30 days after the payment deadline
    future_cutoff = Timex.shift(due_date, days: 30)

    Timex.between?(transaction_date, past_cutoff, future_cutoff, inclusive: true)
  end

  @spec within_amount_window(%CostInvoice{} | %SalesInvoice{}, %Transaction{}) :: boolean()
  defp within_amount_window(cost_invoice = %CostInvoice{}, transaction = %Transaction{}) do
    is_transaction_a_cost = Decimal.lt?(transaction.transaction_amount, 0)

    total_amount =
      Currencies.normalize_amount_to_pln(
        cost_invoice.total_amount |> Decimal.abs(),
        cost_invoice.currency,
        cost_invoice.issue_date
      )

    normalized_transaction_amount =
      Currencies.normalize_amount_to_pln(
        transaction.transaction_amount |> Decimal.abs(),
        transaction.transaction_currency,
        transaction.booking_date
      )

    lower_boundary = Decimal.mult(total_amount, Decimal.new("0.7"))
    upper_boundary = Decimal.mult(total_amount, Decimal.new("1.5"))

    is_between_amount_window =
      Decimal.gte?(normalized_transaction_amount, lower_boundary) and
        Decimal.lte?(normalized_transaction_amount, upper_boundary)

    is_transaction_a_cost and is_between_amount_window
  end

  defp within_amount_window(sales_invoice = %SalesInvoice{}, transaction = %Transaction{}) do
    is_transaction_a_sale = Decimal.gt?(transaction.transaction_amount, 0)

    total_amount =
      Currencies.normalize_amount_to_pln(
        SalesInvoice.get_gross_value(sales_invoice) |> Decimal.abs(),
        sales_invoice.currency,
        sales_invoice.issue_date
      )

    normalized_transaction_amount =
      Currencies.normalize_amount_to_pln(
        transaction.transaction_amount |> Decimal.abs(),
        transaction.transaction_currency,
        transaction.booking_date
      )

    lower_boundary = Decimal.mult(total_amount, Decimal.new("0.9"))
    upper_boundary = Decimal.mult(total_amount, Decimal.new("1.1"))

    is_between_amount_window =
      Decimal.gte?(normalized_transaction_amount, lower_boundary) and
        Decimal.lte?(normalized_transaction_amount, upper_boundary)

    is_transaction_a_sale and is_between_amount_window
  end
end
