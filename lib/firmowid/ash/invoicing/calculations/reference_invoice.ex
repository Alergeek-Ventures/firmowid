defmodule Firmowid.Ash.Invoicing.Calculations.ReferenceInvoice do
  @moduledoc """
  Returns the "before" snapshot for a correction (KOR) invoice.

  For a VAT invoice, returns `nil` (VAT invoices have no reference).
  For a KOR invoice, returns the previous correction in timestamp order,
  or the original VAT invoice if this is the first correction.

  Requires `corrected_invoice` with `corrections` (and their `sales_invoice_items`)
  to be loaded before this calculation is invoked.
  """
  use Ash.Resource.Calculation

  alias Firmowid.Ash.Invoicing.Utilities.SafeTimestamp

  @impl true
  def load(_query, _opts, _context) do
    [:corrected_invoice, corrected_invoice: [corrections: :sales_invoice_items]]
  end

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, &reference_for/1)
  end

  defp reference_for(%{ksef_invoice_kind: :vat}), do: nil

  defp reference_for(%{ksef_invoice_kind: :kor, corrected_invoice: %{corrections: corrections}} = invoice)
       when is_list(corrections) do
    my_timestamp = SafeTimestamp.safe_timestamp(invoice)

    corrections
    |> Enum.reject(fn correction ->
      correction.id == invoice.id or SafeTimestamp.safe_after?(correction, my_timestamp)
    end)
    |> Enum.max_by(&SafeTimestamp.safe_timestamp/1, DateTime, fn -> invoice.corrected_invoice end)
  end

  defp reference_for(_), do: nil
end
