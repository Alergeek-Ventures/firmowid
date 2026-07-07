defmodule Firmowid.Ash.Invoicing.Calculations.CooperationValue do
  @moduledoc """
  Calculates the cooperation value for a given counterparty.
  If there are invoices with single currency, it returns the total value and that currency.
  If there are invoices with multiple currencies, it converts all values to PLN and returns the total in PLN.
  Counterparty with no invoices returns nil.
  """
  use Ash.Resource.Calculation

  alias Firmowid.Ash.Currencies.Converter

  @impl true
  def load(_query, _opts, _context) do
    [sales_invoices: [:gross_value, :currency, :sale_date, :reconciliation_status]]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn counterparty ->
      confirmed_invoices =
        Enum.filter(counterparty.sales_invoices, &(&1.reconciliation_status == :matched))

      confirmed_currencies = Enum.map(confirmed_invoices, & &1.currency)

      case Enum.uniq(confirmed_currencies) do
        [] ->
          nil

        [currency] ->
          %{
            total: Enum.reduce(confirmed_invoices, Decimal.new(0), &Decimal.add(&1.gross_value, &2)),
            currency: currency
          }

        _ ->
          total_in_pln =
            Enum.reduce(confirmed_invoices, Decimal.new(0), fn invoice, acc ->
              invoice.gross_value
              |> Converter.normalize_amount_to_pln(invoice.currency, invoice.sale_date)
              |> Decimal.add(acc)
            end)

          %{total: total_in_pln, currency: "PLN"}
      end
    end)
  end
end
