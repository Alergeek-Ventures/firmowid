defmodule Firmowid.Taxes.Forecast.Corrections do
  @moduledoc """
  What a sales correction changes: the difference of one of its amounts against
  the state the invoice had before it.
  """

  alias Firmowid.Invoicing.SalesInvoice

  @doc """
  Returns how much `field` (`:vat_value` or `:net_value`) of a correction
  differs from the invoice it corrects, or from the correction before it.

  The correction needs `corrected_invoice` loaded with its `corrections`, and
  all of them the `field`.
  """
  @spec change(SalesInvoice.t(), :vat_value | :net_value) :: Decimal.t()
  def change(%{corrected_invoice: corrected} = correction, field) do
    before =
      corrected.corrections
      |> Enum.take_while(&(&1.id != correction.id))
      |> Enum.filter(& &1.invoice_number)
      |> List.last(corrected)

    Decimal.sub(value(correction, field), value(before, field))
  end

  # An invoice without lines has nothing to sum.
  defp value(invoice, field), do: Map.fetch!(invoice, field) || Decimal.new(0)
end
