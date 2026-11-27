defmodule Firmowid.Taxes.Forecast.Pit do
  @moduledoc """
  Forecasts a year's PIT advances of one owner (a sole proprietor or a civil
  partner) from their share of the company's income entries and their monthly
  ZUS contributions (`Firmowid.Taxes.Forecast.Zus.contributions/4`).

  Advances are paid monthly or quarterly and computed cumulatively from
  1 January. Each is due on the 20th of the month after the period, so on
  20 January of the next year for the last one (art. 44 ust. 6 of the PIT Act;
  art. 21 ust. 1 and 1a of the lump-sum act). The advance is the tax to the end
  of the period less the advances of the earlier periods, not below zero, so a
  loss lowers the later advances. The tax is rounded to a full złoty
  (art. 63 § 1 of the Tax Ordinance), and so is the base.

  Depending on the partner's `income_tax`:

    * `:tax_scale` (art. 27 ust. 1, art. 26 ust. 1 pkt 2, art. 44 ust. 3): the
      income less the social contributions is taxed at 12% less 3 600 zł up to
      120 000 zł, and above it at 10 800 zł plus 32% of the excess;
    * `:flat_tax` (art. 30c): the income less the social and health
      contributions (the health ones up to a yearly limit) is taxed at 19%;
    * `:lump_sum` (art. 11 and 12 of the lump-sum act): the revenue less the
      social contributions and half of the health ones is taxed at the chosen
      rate; costs do not count.

  The entries may include projected ones (`Firmowid.Taxes.Forecast.Projection`)
  that count like the rest; `details` tells how much of the cumulative revenue
  and costs they make (`projected_revenue`, `projected_costs`), and how much of
  the cumulative revenue comes from bank transfers without an invoice
  (`transfer_revenue`, booked ones only).

  The social contributions deducted are pension, disability, sickness and
  accident, not the Labour Fund.

  Simplifications: no other income, joint filing, reliefs, losses of earlier
  years or depreciation; contributions are deducted for the month they are for,
  not when paid; advances up to 1 000 zł are not skipped; a lump-sum rate of
  8.5% is not raised to 12.5% above 100 000 zł of revenue.
  """
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.Period
  alias Firmowid.Taxes.Forecast.Rates
  alias Firmowid.Taxes.Forecast.Zus

  @scale_threshold Decimal.new(120_000)
  @scale_deduction Decimal.new(3_600)
  @scale_first_tax Decimal.new(10_800)

  @due_day 20

  @type partner :: %{
          required(:income_tax) => :tax_scale | :flat_tax | :lump_sum,
          required(:lump_sum_rate) => Decimal.t() | nil,
          required(:pit_advances) => Period.frequency(),
          optional(atom()) => any()
        }

  @doc "Returns the day of the month after the period on which its PIT advance is due."
  @spec due_day() :: 1..28
  def due_day, do: @due_day

  @doc "Returns the description of the PIT advance for `period`."
  @spec description(Period.t()) :: String.t()
  def description(period), do: gettext("PIT advance for %{period}", period: Period.name(period))

  @doc "Returns one forecast for each period of `year`, from entries of any year."
  @spec forecast([Income.entry()], partner(), [Zus.contribution()], String.t(), integer()) :: [
          map()
        ]
  def forecast(entries, partner, contributions, member_id, year) do
    rates = Rates.for_year(year)
    january = Date.new!(year, 1, 1)

    {forecasts, _paid} =
      year
      |> Period.of_year(partner.pit_advances)
      |> Enum.map_reduce(Decimal.new(0), fn period, advances_before ->
        %{revenue: revenue, costs: costs} = sums = Income.between(entries, january, period.last)
        income = Decimal.sub(revenue, costs)
        counted = Enum.filter(contributions, &(Date.compare(&1.period.last, period.last) != :gt))
        social = total(counted, :social_deductible)
        health = total(counted, :health)

        {deducted_health, base, rate, tax} = tax(partner, rates, revenue, income, social, health)
        advance = tax |> Decimal.sub(advances_before) |> Decimal.max(0)

        forecast = %{
          kind: :pit,
          period: period.key,
          period_start: period.first,
          period_end: period.last,
          amount: advance,
          due_date: Period.due_date(period, @due_day),
          description: description(period),
          member_id: member_id,
          details: %{
            revenue: Decimal.round(revenue, 2),
            transfer_revenue: Decimal.round(sums.transfer_revenue, 2),
            costs: Decimal.round(costs, 2),
            projected_revenue: Decimal.round(sums.projected_revenue, 2),
            projected_costs: Decimal.round(sums.projected_costs, 2),
            income: Decimal.round(income, 2),
            social_deducted: social,
            health_deducted: deducted_health,
            tax_base: base,
            tax: tax,
            advances_before: advances_before,
            income_tax: partner.income_tax,
            rate: rate,
            rates_year: rates.year
          }
        }

        {forecast, Decimal.add(advances_before, advance)}
      end)

    forecasts
  end

  # Returns the health contributions deducted, the base, the rate in percent
  # (nil on the tax scale, which has two) and the tax.
  # The tax scale deducts no health contribution.
  defp tax(%{income_tax: :tax_scale}, _rates, _revenue, income, social, _health) do
    base = base(income, social)

    tax =
      if Decimal.compare(base, @scale_threshold) == :gt,
        do:
          base
          |> Decimal.sub(@scale_threshold)
          |> Decimal.mult("0.32")
          |> Decimal.add(@scale_first_tax),
        else: base |> Decimal.mult("0.12") |> Decimal.sub(@scale_deduction) |> Decimal.max(0)

    {Decimal.new(0), base, nil, whole(tax)}
  end

  defp tax(%{income_tax: :flat_tax}, rates, _revenue, income, social, health) do
    deducted = Decimal.min(health, rates.flat_tax_health_limit)
    base = base(income, Decimal.add(social, deducted))

    {deducted, base, Decimal.new(19), base |> Decimal.mult("0.19") |> whole()}
  end

  defp tax(%{income_tax: :lump_sum, lump_sum_rate: rate}, _rates, revenue, _income, social, health) do
    deducted = Decimal.div(health, 2)
    base = base(revenue, Decimal.add(social, deducted))

    {deducted, base, rate, base |> Decimal.mult(rate) |> Decimal.div(100) |> whole()}
  end

  defp base(income, deductions), do: income |> Decimal.sub(deductions) |> Decimal.round(0, :half_up) |> Decimal.max(0)

  defp whole(amount), do: Decimal.round(amount, 0, :half_up)

  defp total(contributions, key), do: Enum.reduce(contributions, Decimal.new(0), &Decimal.add(&1[key], &2))
end
