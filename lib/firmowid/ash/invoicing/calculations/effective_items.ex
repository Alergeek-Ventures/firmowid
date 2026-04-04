defmodule Firmowid.Ash.Invoicing.Calculations.EffectiveItems do
  @moduledoc """
  Module calculation that returns the correction-aware items for a sales invoice.

  If the invoice has a latest correction with loaded items, returns those.
  Otherwise returns the invoice's own items. Encapsulates the "which items
  are current?" logic in one place — no `||` patterns in callers.

  Value calculations (`InvoiceNetValue`, etc.) can depend on this to compute
  on the correct items automatically.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context) do
    [:sales_invoice_items, latest_correction: :sales_invoice_items]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.latest_correction do
        %{sales_invoice_items: items} when is_list(items) -> items
        _ -> record.sales_invoice_items
      end
    end)
  end
end
