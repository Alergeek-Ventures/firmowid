defmodule Firmowid.Ash.Invoicing.Matching.Windowing do
  @moduledoc """
  Pre-filters transactions to a broad candidate set for invoice matching.

  The filter is intentionally permissive and is meant only as the first
  narrowing step before detailed matching.
  """

  alias Firmowid.Ash.Currencies.Converter, as: Currencies
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.Matching.RateDate
  alias Firmowid.Ash.Invoicing.SalesInvoice

  # TODO: re-add Transaction struct constraints once legacy Ecto schema is removed

  @doc """
  Pre-filter the transactions list to only include ones
  that are sligthly within a time window and
  amount window. These windows are very generous.
  """
  @spec pre_filter_invoice_transactions(CostInvoice.t() | SalesInvoice.t(), [map()]) :: [map()]
  def pre_filter_invoice_transactions(%CostInvoice{} = cost_invoice, transactions) do
    if is_nil(cost_invoice.issue_date) or is_nil(cost_invoice.due_date) do
      []
    else
      Enum.filter(transactions, fn transaction ->
        within_time_window?(
          cost_invoice.issue_date,
          cost_invoice.due_date,
          transaction.booking_date
        ) and
          within_amount_window(cost_invoice, transaction)
      end)
    end
  end

  def pre_filter_invoice_transactions(%SalesInvoice{} = sales_invoice, transactions) do
    if is_nil(sales_invoice.issue_date) or is_nil(sales_invoice.due_date) do
      []
    else
      Enum.filter(transactions, fn transaction ->
        within_time_window?(
          sales_invoice.issue_date,
          sales_invoice.due_date,
          transaction.booking_date
        ) and
          within_amount_window(sales_invoice, transaction)
      end)
    end
  end

  @spec within_time_window?(Date.t(), Date.t(), Date.t()) :: boolean()
  defp within_time_window?(issue_date, due_date, transaction_date) do
    # up to 10 days before it was issued
    past_cutoff = Date.shift(issue_date, day: -30)
    # up to 30 days after the payment deadline
    future_cutoff = Date.shift(due_date, day: 60)

    Date.compare(transaction_date, past_cutoff) in [:gt, :eq] and
      Date.compare(transaction_date, future_cutoff) in [:lt, :eq]
  end

  @spec within_amount_window(CostInvoice.t() | SalesInvoice.t(), map()) :: boolean()
  defp within_amount_window(%CostInvoice{} = cost_invoice, transaction) do
    transaction_amount = Money.to_decimal(transaction.amount)
    transaction_currency = transaction.amount |> Money.to_currency_code() |> Atom.to_string()

    is_transaction_a_cost = Decimal.lt?(transaction_amount, 0)

    total_amount =
      cost_invoice.total_amount
      |> Decimal.abs()
      |> Currencies.normalize_amount_to_pln(
        cost_invoice.currency,
        RateDate.normalize_rate_date(cost_invoice.issue_date)
      )

    normalized_transaction_amount =
      transaction_amount
      |> Decimal.abs()
      |> Currencies.normalize_amount_to_pln(
        transaction_currency,
        RateDate.normalize_rate_date(transaction.booking_date)
      )

    lower_boundary = Decimal.mult(total_amount, Decimal.new("0.9"))
    upper_boundary = Decimal.mult(total_amount, Decimal.new("1.1"))

    is_between_amount_window =
      Decimal.gte?(normalized_transaction_amount, lower_boundary) and
        Decimal.lte?(normalized_transaction_amount, upper_boundary)

    is_transaction_a_cost and is_between_amount_window
  end

  defp within_amount_window(%SalesInvoice{} = sales_invoice, transaction) do
    transaction_amount = Money.to_decimal(transaction.amount)
    transaction_currency = transaction.amount |> Money.to_currency_code() |> Atom.to_string()

    is_transaction_a_sale = Decimal.gt?(transaction_amount, 0)

    total_amount =
      sales_invoice.gross_value
      |> Decimal.abs()
      |> Currencies.normalize_amount_to_pln(
        sales_invoice.currency,
        RateDate.normalize_rate_date(sales_invoice.issue_date)
      )

    normalized_transaction_amount =
      transaction_amount
      |> Decimal.abs()
      |> Currencies.normalize_amount_to_pln(
        transaction_currency,
        RateDate.normalize_rate_date(transaction.booking_date)
      )

    lower_boundary = Decimal.mult(total_amount, Decimal.new("0.9"))
    upper_boundary = Decimal.mult(total_amount, Decimal.new("1.1"))

    is_between_amount_window =
      Decimal.gte?(normalized_transaction_amount, lower_boundary) and
        Decimal.lte?(normalized_transaction_amount, upper_boundary)

    is_transaction_a_sale and is_between_amount_window
  end
end
