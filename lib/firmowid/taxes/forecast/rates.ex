defmodule Firmowid.Taxes.Forecast.Rates do
  @moduledoc """
  The yearly amounts the forecasts of an owner's ZUS contributions and PIT
  advances are computed from.

  A year without figures uses the latest known year's: next year's amounts are
  announced late and a forecast must not vanish in January. Every forecast
  carries the year its figures come from as `rates_year`. Percent rates that do
  not change yearly live in the modules that use them.
  """

  @type t :: %{
          year: integer(),
          full_base: Decimal.t(),
          preferential_base: Decimal.t(),
          minimum_wage: Decimal.t(),
          minimum_health_january: Decimal.t(),
          minimum_health: Decimal.t(),
          lump_sum_health: [{limit :: Decimal.t(), amount :: Decimal.t()}],
          lump_sum_health_top: Decimal.t(),
          flat_tax_health_limit: Decimal.t()
        }

  # 2026: https://www.zus.pl/firmy/rozliczenia-z-zus/skladki-na-ubezpieczenia and
  # https://www.zus.pl/-/informacja-w-sprawie-podstawy-wymiaru-sk%C5%82adki-oraz-kwoty-sk%C5%82adki-na-ubezpieczenie-zdrowotne-w-2026-r.;
  # the flat tax limit: obwieszczenie Ministra Finansów, M.P. 2025 poz. 1274.
  @rates %{
    2026 => %{
      # 60% of the forecast average wage of 9 420 zł.
      full_base: "5652.00",
      # 30% of the minimum wage.
      preferential_base: "1441.80",
      minimum_wage: "4806.00",
      # The minimum health contribution is 9% of the minimum wage of the month.
      minimum_health_january: "314.96",
      minimum_health: "432.54",
      # The lump sum health contribution by revenue since 1 January: up to 60 000 zł,
      # up to 300 000 zł, and above.
      lump_sum_health: [{"60000", "498.35"}, {"300000", "830.58"}],
      lump_sum_health_top: "1495.04",
      flat_tax_health_limit: "14100"
    }
  }

  @doc "Returns the figures of `year`, or of the latest known year before it."
  @spec for_year(integer()) :: t()
  def for_year(year) do
    known = Map.keys(@rates)
    used = known |> Enum.filter(&(&1 <= year)) |> Enum.max(fn -> Enum.min(known) end)

    @rates
    |> Map.fetch!(used)
    |> Map.new(fn
      {:lump_sum_health, tiers} ->
        {:lump_sum_health, for({limit, amount} <- tiers, do: {Decimal.new(limit), Decimal.new(amount)})}

      {key, amount} ->
        {key, Decimal.new(amount)}
    end)
    |> Map.put(:year, used)
  end

  @doc "Returns the minimum health contribution of `month` (1 to 12)."
  @spec minimum_health(t(), 1..12) :: Decimal.t()
  def minimum_health(rates, 1), do: rates.minimum_health_january
  def minimum_health(rates, _month), do: rates.minimum_health
end
