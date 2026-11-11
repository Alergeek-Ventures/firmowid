defmodule FirmowidWeb.Analysis.Utilities.Amounts do
  @moduledoc "Amounts and shares of a total as the analysis views print them."

  alias Firmowid.Cldr.Number

  @doc "An amount in whole złoty."
  @spec whole_money(Decimal.t() | integer()) :: String.t()
  def whole_money(amount), do: Number.to_string!(amount, currency: :PLN, fractional_digits: 0)

  @doc "The share of a positive `total` as a percent label; empty otherwise."
  @spec ratio(Decimal.t(), Decimal.t()) :: String.t()
  def ratio(amount, total) do
    if Decimal.positive?(total),
      do: amount |> Decimal.div(total) |> Number.to_string!(format: :percent),
      else: ""
  end

  @doc "The share of a positive `total` in percent to one decimal, for a bar width; 0.0 otherwise."
  @spec share_percent(Decimal.t(), Decimal.t()) :: float()
  def share_percent(amount, total) do
    if Decimal.positive?(total),
      do:
        amount
        |> Decimal.div(total)
        |> Decimal.mult(100)
        |> Decimal.round(1)
        |> Decimal.to_float(),
      else: 0.0
  end
end
