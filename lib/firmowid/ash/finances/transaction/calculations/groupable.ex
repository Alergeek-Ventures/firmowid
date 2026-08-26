defmodule Firmowid.Ash.Finances.Transaction.Calculations.Groupable do
  @moduledoc "Determines whether a transaction can be grouped for invoicing."

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:counterparty_name, :skip_invoicing, :has_cost_invoices?, :has_sales_invoices?]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn transaction ->
      useful_counterparty?(transaction.counterparty_name) and
        transaction.skip_invoicing == false and
        transaction.has_cost_invoices? == false and transaction.has_sales_invoices? == false
    end)
  end

  defp useful_counterparty?(value) when is_binary(value) do
    trimmed = String.trim(value)
    trimmed != "" and String.upcase(trimmed) != "N/A"
  end

  defp useful_counterparty?(_value), do: false
end
