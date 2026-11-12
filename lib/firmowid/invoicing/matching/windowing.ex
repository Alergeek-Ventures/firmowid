defmodule Firmowid.Invoicing.Matching.Windowing do
  @moduledoc """
  Pre-filters transactions to a broad candidate set for invoice matching.

  The filter is intentionally permissive and is meant only as the first
  narrowing step before detailed matching.
  """

  alias Firmowid.Currencies.Converter, as: Currencies
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.Matching.RateDate
  alias Firmowid.Invoicing.SalesInvoice

  @doc """
  Keeps the transactions on the invoice's side (outgoing for a cost invoice,
  incoming for a sales invoice) booked from 30 days before the issue date to
  60 days after the due date, whose amount in PLN is within 10% of the invoice's.
  """
  @spec pre_filter_invoice_transactions(CostInvoice.t() | SalesInvoice.t(), [Transaction.t()]) ::
          [Transaction.t()]
  def pre_filter_invoice_transactions(%{issue_date: issue_date, due_date: due_date}, _transactions)
      when is_nil(issue_date) or is_nil(due_date), do: []

  def pre_filter_invoice_transactions(%module{} = invoice, transactions) when module in [CostInvoice, SalesInvoice] do
    Enum.filter(transactions, fn transaction ->
      within_time_window?(invoice.issue_date, invoice.due_date, transaction.booking_date) and
        within_amount_window?(invoice, transaction) and
        on_invoice_side?(module, transaction)
    end)
  end

  defp within_time_window?(issue_date, due_date, transaction_date) do
    past_cutoff = Date.shift(issue_date, day: -30)
    future_cutoff = Date.shift(due_date, day: 60)

    Date.compare(transaction_date, past_cutoff) in [:gt, :eq] and
      Date.compare(transaction_date, future_cutoff) in [:lt, :eq]
  end

  defp on_invoice_side?(CostInvoice, transaction), do: Decimal.lt?(Money.to_decimal(transaction.amount), 0)

  defp on_invoice_side?(SalesInvoice, transaction), do: Decimal.gt?(Money.to_decimal(transaction.amount), 0)

  defp within_amount_window?(invoice, transaction) do
    invoice_amount = pln_amount(invoice.effective_amount, invoice.issue_date)
    transaction_amount = pln_amount(transaction.amount, transaction.booking_date)

    Decimal.gte?(transaction_amount, Decimal.mult(invoice_amount, Decimal.new("0.9"))) and
      Decimal.lte?(transaction_amount, Decimal.mult(invoice_amount, Decimal.new("1.1")))
  end

  defp pln_amount(money, date) do
    money
    |> Money.to_decimal()
    |> Decimal.abs()
    |> Currencies.normalize_amount_to_pln(
      money |> Money.to_currency_code() |> Atom.to_string(),
      RateDate.normalize_rate_date(date)
    )
  end
end
