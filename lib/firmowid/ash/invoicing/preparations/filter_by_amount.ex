defmodule Firmowid.Ash.Invoicing.Preparations.FilterByAmount do
  @moduledoc """
  Preparation that filters invoice listings by amount regardless of sign.

  Cost invoices are stored as negative amounts and corrections may change the sign,
  so `amount_from` and `amount_to` compare the absolute value, both inclusive.
  With `merge_corrections` the listing shows each invoice after its corrections,
  so the filter compares `effective_amount`; otherwise each document's own `amount`.
  """
  use Ash.Resource.Preparation

  import Ash.Expr, only: [expr: 1]

  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    amount =
      if query.arguments[:merge_corrections],
        do: expr(effective_amount[:amount]),
        else: expr(amount[:amount])

    # Ash has no abs/1; the explicit type keeps Ash from comparing the result as Money.
    absolute = expr(type(fragment("abs(?)", ^amount), :decimal))

    query
    |> filter_if(query.arguments[:amount_from], &expr(^absolute >= ^&1))
    |> filter_if(query.arguments[:amount_to], &expr(^absolute <= ^&1))
  end

  defp filter_if(query, nil, _filter), do: query
  defp filter_if(query, bound, filter), do: Ash.Query.filter(query, ^filter.(bound))
end
