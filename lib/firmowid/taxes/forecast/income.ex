defmodule Firmowid.Taxes.Forecast.Income do
  @moduledoc """
  The income of a company from a list of entries: revenue and costs, net of
  VAT, in PLN, each on the day it counts. Income taxes build on it.
  """

  alias Firmowid.Taxes.Forecast.Projection

  @type entry :: %{
          required(:side) => :revenue | :cost,
          required(:amount) => Decimal.t(),
          required(:date) => Date.t(),
          optional(:projected?) => boolean()
        }

  @doc """
  Returns the revenue and the costs of the entries dated from `first` to `last`, both inclusive,
  and the part of each that comes from projected entries (see `Firmowid.Taxes.Forecast.Projection`).
  """
  @spec between([entry()], Date.t(), Date.t()) :: %{
          revenue: Decimal.t(),
          costs: Decimal.t(),
          projected_revenue: Decimal.t(),
          projected_costs: Decimal.t()
        }
  def between(entries, first, last) do
    in_range = Enum.filter(entries, &(&1.date in Date.range(first, last)))
    projected = Enum.filter(in_range, &Projection.projected?/1)

    %{
      revenue: total(in_range, :revenue),
      costs: total(in_range, :cost),
      projected_revenue: total(projected, :revenue),
      projected_costs: total(projected, :cost)
    }
  end

  @doc """
  Returns the entries with every amount multiplied by `share` percent: an
  owner's part of the company's income (art. 8 ust. 1 of the PIT Act).
  """
  @spec scale([entry()], Decimal.t()) :: [entry()]
  def scale(entries, share) do
    Enum.map(entries, &%{&1 | amount: &1.amount |> Decimal.mult(share) |> Decimal.div(100)})
  end

  defp total(entries, side) do
    entries
    |> Enum.filter(&(&1.side == side))
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.amount, &2))
  end
end
