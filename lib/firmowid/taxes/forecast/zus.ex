defmodule Firmowid.Taxes.Forecast.Zus do
  @moduledoc """
  Forecasts a year's ZUS contributions of one owner (a sole proprietor or a
  civil partner) from their share of the company's income entries.

  One forecast for each month, due on the 20th of the next month (art. 47
  ust. 1 of the social insurance system act: payers without legal personality).

  The social base follows the partner's `social_insurance`: the full or the
  preferential base of `Firmowid.Taxes.Forecast.Rates`, nothing for
  `:start_relief` and `:none`, and for `:small_plus` (Mały ZUS Plus) half of the
  average monthly income of the previous calendar year, kept between the
  preferential and the full base. That income is revenue less costs, or half of
  the revenue on the lump sum, and not below zero. Pension, disability and
  accident contributions (and sickness with `voluntary_sickness`) are percents
  of the base rounded to the grosz; the Labour Fund with the Solidarity Fund is
  added only when the base reaches the minimum wage.

  The health contribution of a month is, on the tax scale (9%) and the flat tax
  (4.9%), that percent of the income of the previous month less one month of
  social contributions, not below the minimum of the month. On the lump sum it
  is a fixed amount chosen by the revenue from 1 January to the end of the month.

  Projected entries (`Firmowid.Taxes.Forecast.Projection`) count like the rest, so the
  lump-sum health contribution of the running month sees the typical rest of its revenue;
  the other health contribution reads the previous month, which is complete.

  Simplifications: contributions count in the month they are for, not when paid;
  the health contribution uses each month's own income instead of the cumulative
  method and has no yearly settlement; Mały ZUS Plus assumes the whole previous
  year in business and counts only what Firmowid knows of it; the age exemption
  from the Labour Fund and other insurance titles are unknown.
  """
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.Period
  alias Firmowid.Taxes.Forecast.Rates

  # Percent rates of the base; the sources are the ZUS contribution tables.
  @pension Decimal.new("19.52")
  @disability Decimal.new("8")
  @sickness Decimal.new("2.45")
  @labour_fund Decimal.new("2.45")
  @health_scale Decimal.new("9")
  @health_flat_tax Decimal.new("4.9")

  @due_day 20

  @type partner :: %{
          required(:income_tax) => :tax_scale | :flat_tax | :lump_sum,
          required(:social_insurance) => :start_relief | :preferential | :small_plus | :full | :none,
          required(:voluntary_sickness) => boolean(),
          optional(atom()) => any()
        }

  @type contribution :: %{
          period: Period.t(),
          social_base: Decimal.t(),
          pension: Decimal.t(),
          disability: Decimal.t(),
          accident: Decimal.t(),
          sickness: Decimal.t(),
          labour_fund: Decimal.t(),
          social_deductible: Decimal.t(),
          health: Decimal.t(),
          health_base: Decimal.t(),
          rates_year: integer()
        }

  @doc "Returns the day of the month after the period on which its ZUS contribution is due."
  @spec due_day() :: 1..28
  def due_day, do: @due_day

  @doc """
  Returns the monthly contributions of `year` in order, from the partner's
  entries of the year and the one before. `social_deductible` is the part of
  the social contributions that income tax deducts: all but the Labour Fund.
  """
  @spec contributions([Income.entry()], partner(), Decimal.t(), integer()) :: [contribution()]
  def contributions(entries, partner, accident_rate, year) do
    rates = Rates.for_year(year)

    for period <- Period.of_year(year, :monthly) do
      base = social_base(entries, partner, rates, year)
      social = social(base, partner, accident_rate, rates)

      deductible =
        social |> Map.take([:pension, :disability, :accident, :sickness]) |> Map.values() |> sum()

      {health_base, health} = health(entries, partner, period, deductible, rates)

      Map.merge(social, %{
        period: period,
        social_base: base,
        social_deductible: deductible,
        health: health,
        health_base: health_base,
        rates_year: rates.year
      })
    end
  end

  @doc "Returns one forecast for each month of `year` from the `contributions/4` of the partner."
  @spec forecast([contribution()], String.t()) :: [map()]
  def forecast(contributions, member_id) do
    Enum.map(contributions, fn contribution ->
      %{period: period} = contribution

      social =
        sum([
          contribution.pension,
          contribution.disability,
          contribution.accident,
          contribution.sickness,
          contribution.labour_fund
        ])

      %{
        kind: :zus,
        period: period.key,
        period_start: period.first,
        period_end: period.last,
        amount: Decimal.add(social, contribution.health),
        due_date: Period.due_date(period, @due_day),
        description: gettext("ZUS for %{period}", period: Period.name(period)),
        member_id: member_id,
        details:
          Map.take(contribution, [
            :pension,
            :disability,
            :accident,
            :sickness,
            :labour_fund,
            :health,
            :social_base,
            :health_base,
            :rates_year
          ])
      }
    end)
  end

  defp social_base(_entries, %{social_insurance: insurance}, _rates, _year) when insurance in [:start_relief, :none],
    do: Decimal.new(0)

  defp social_base(_entries, %{social_insurance: :full}, rates, _year), do: rates.full_base

  defp social_base(_entries, %{social_insurance: :preferential}, rates, _year), do: rates.preferential_base

  defp social_base(entries, %{social_insurance: :small_plus} = partner, rates, year) do
    first = Date.new!(year - 1, 1, 1)
    last = Date.new!(year - 1, 12, 31)
    %{revenue: revenue, costs: costs} = Income.between(entries, first, last)

    income =
      if partner.income_tax == :lump_sum,
        do: Decimal.div(revenue, 2),
        else: Decimal.sub(revenue, costs)

    income
    |> Decimal.max(0)
    |> Decimal.div(Date.diff(last, first) + 1)
    |> Decimal.mult(30)
    |> Decimal.div(2)
    |> Decimal.max(rates.preferential_base)
    |> Decimal.min(rates.full_base)
    |> Decimal.round(2, :half_up)
  end

  defp social(base, partner, accident_rate, rates) do
    # A zero base gives zero amounts, and stays below the minimum wage for the Labour Fund.
    %{
      pension: percent(base, @pension),
      disability: percent(base, @disability),
      accident: percent(base, accident_rate),
      sickness: if(partner.voluntary_sickness, do: percent(base, @sickness), else: Decimal.new(0)),
      labour_fund:
        if(Decimal.compare(base, rates.minimum_wage) == :lt,
          do: Decimal.new(0),
          else: percent(base, @labour_fund)
        )
    }
  end

  defp health(entries, %{income_tax: :lump_sum}, period, _deductible, rates) do
    january = %{period.first | month: 1, day: 1}
    %{revenue: revenue} = Income.between(entries, january, period.last)
    revenue = Decimal.round(revenue, 2)

    [{up_to_first, first}, {up_to_second, second}] = rates.lump_sum_health

    amount =
      cond do
        Decimal.compare(revenue, up_to_first) != :gt -> first
        Decimal.compare(revenue, up_to_second) != :gt -> second
        true -> rates.lump_sum_health_top
      end

    {revenue, amount}
  end

  defp health(entries, partner, period, deductible, rates) do
    last_month_end = Date.add(period.first, -1)

    %{revenue: revenue, costs: costs} =
      Income.between(entries, Date.beginning_of_month(last_month_end), last_month_end)

    base =
      revenue
      |> Decimal.sub(costs)
      |> Decimal.sub(deductible)
      |> Decimal.max(0)
      |> Decimal.round(2, :half_up)

    rate = if partner.income_tax == :flat_tax, do: @health_flat_tax, else: @health_scale

    {base, Decimal.max(percent(base, rate), Rates.minimum_health(rates, period.first.month))}
  end

  defp percent(base, rate) do
    base |> Decimal.mult(rate) |> Decimal.div(100) |> Decimal.round(2, :half_up)
  end

  defp sum(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)
end
