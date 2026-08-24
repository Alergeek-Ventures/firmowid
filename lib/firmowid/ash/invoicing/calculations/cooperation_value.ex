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
    [sales_invoices: [:effective_amount, :sale_date, :reconciliation_status]]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn counterparty ->
      confirmed_invoices =
        Enum.filter(counterparty.sales_invoices, &(&1.reconciliation_status == :matched))

      confirmed_currencies = Enum.map(confirmed_invoices, &invoice_currency/1)

      case Enum.uniq(confirmed_currencies) do
        [] ->
          nil

        [currency] ->
          %{
            total:
              confirmed_invoices
              |> Enum.map(& &1.effective_amount)
              |> Enum.reduce(Money.new!(currency, 0), &Money.add!/2)
              |> Money.to_decimal(),
            currency: currency
          }

        _ ->
          total_in_pln =
            Enum.reduce(confirmed_invoices, Decimal.new(0), fn invoice, acc ->
              invoice.effective_amount
              |> Money.to_decimal()
              |> Converter.normalize_amount_to_pln(invoice_currency(invoice), invoice.sale_date)
              |> Decimal.add(acc)
            end)

          %{total: total_in_pln, currency: "PLN"}
      end
    end)
  end

  defp invoice_currency(invoice) do
    invoice.effective_amount
    |> Money.to_currency_code()
    |> Atom.to_string()
  end
end
