defmodule Firmowid.Taxes.Forecast.Cit do
  @moduledoc """
  Forecasts a year's CIT advances of a limited company from its income entries.

  Each period's advance is computed cumulatively from 1 January (art. 25 ust. 1
  and 1b of the CIT Act): the income to the end of the period, rounded to a full
  złoty and not below zero, taxed at 9% (`:reduced`) or 19% (`:standard`) and
  rounded to a full złoty (art. 63 § 1 of the Tax Ordinance), less the advances
  of the earlier periods, not below zero. A loss in a period therefore lowers
  the later advances. It is due on the 20th of the month after the period, so
  20 January of the next year for the last one (art. 25 ust. 1a and 1c).

  The entries may include projected ones (`Firmowid.Taxes.Forecast.Projection`)
  that count like the rest; `details` tells how much of the cumulative revenue
  and costs they make (`projected_revenue`, `projected_costs`), and how much of
  the cumulative revenue comes from bank transfers without an invoice
  (`transfer_revenue`, booked ones only).

  The `:simplified` form pays a fixed monthly amount taken from an earlier tax
  return, which Firmowid does not have, so it forecasts nothing.

  Simplifications: no depreciation, non-deductible costs or losses of earlier
  years; the 9% revenue cap and the option of skipping advances up to 1 000 zł
  are not checked; salaries count as the net transfers.
  """
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.Period

  @due_day 20

  @type settings :: %{
          cit_rate: :reduced | :standard,
          cit_advances: :monthly | :quarterly | :simplified
        }

  @doc "Returns the day of the month after the period on which its CIT advance is due."
  @spec due_day() :: 1..28
  def due_day, do: @due_day

  @doc "Returns the description of the CIT advance for `period`."
  @spec description(Period.t()) :: String.t()
  def description(period), do: gettext("CIT advance for %{period}", period: Period.name(period))

  @doc "Returns one forecast for each period of `year`, from entries of any year."
  @spec forecast([Income.entry()], settings(), integer()) :: [map()]
  def forecast(_entries, %{cit_advances: :simplified}, _year), do: []

  def forecast(entries, %{cit_rate: rate, cit_advances: frequency}, year) do
    percent = percent(rate)
    january = Date.new!(year, 1, 1)

    {forecasts, _paid} =
      year
      |> Period.of_year(frequency)
      |> Enum.map_reduce(Decimal.new(0), fn period, advances_before ->
        %{revenue: revenue, costs: costs} = sums = Income.between(entries, january, period.last)
        income = Decimal.sub(revenue, costs)

        tax =
          income
          |> Decimal.round(0, :half_up)
          |> Decimal.max(0)
          |> Decimal.mult(percent)
          |> Decimal.div(100)
          |> Decimal.round(0, :half_up)

        advance = tax |> Decimal.sub(advances_before) |> Decimal.max(0)

        forecast = %{
          kind: :cit,
          period: period.key,
          period_start: period.first,
          period_end: period.last,
          amount: advance,
          due_date: Period.due_date(period, @due_day),
          description: description(period),
          member_id: nil,
          details: %{
            revenue: Decimal.round(revenue, 2),
            transfer_revenue: Decimal.round(sums.transfer_revenue, 2),
            costs: Decimal.round(costs, 2),
            projected_revenue: Decimal.round(sums.projected_revenue, 2),
            projected_costs: Decimal.round(sums.projected_costs, 2),
            income: Decimal.round(income, 2),
            tax: tax,
            advances_before: advances_before,
            rate: percent
          }
        }

        {forecast, Decimal.add(advances_before, advance)}
      end)

    forecasts
  end

  defp percent(:reduced), do: 9
  defp percent(:standard), do: 19
end
