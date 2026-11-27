defmodule Firmowid.Taxes.Forecast.Vat do
  @moduledoc """
  Forecasts a year's VAT payments from the VAT its documents state.

  Each entry is VAT in PLN on the day it counts: output VAT (należny) of what
  was sold, input VAT (naliczony) of what was bought. A period's payment is its
  output VAT less its input VAT, each rounded to a full złoty (art. 63 § 1 of
  the Tax Ordinance), due on the 25th of the month after it (art. 103 ust. 1 of
  the VAT Act).

  Entries may include projected ones (`Firmowid.Taxes.Forecast.Projection`): they count
  like the rest, and `details` tells how much of each figure they make
  (`projected_output_vat`, `projected_input_vat`, zero for a period without any).

  Assumptions: a period with more input than output VAT pays nothing and
  carries the surplus to the next one, and the year starts without a surplus
  from the year before. A refund from the tax office (`:refund` entries) lowers
  the surplus carried into the period it is booked in, down to zero.
  """
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Taxes.Forecast.Period
  alias Firmowid.Taxes.Forecast.Projection

  @due_day 25

  @type entry :: %{
          required(:side) => :output | :input | :refund,
          required(:amount) => Decimal.t(),
          required(:date) => Date.t(),
          optional(:projected?) => boolean()
        }

  @doc "Returns the day of the month after the period on which its VAT is due."
  @spec due_day() :: 1..28
  def due_day, do: @due_day

  @doc "Returns one forecast for each period of `year`; entries of other years are left out."
  @spec forecast([entry()], Period.frequency(), integer()) :: [map()]
  def forecast(entries, frequency, year) do
    {forecasts, _surplus} =
      year
      |> Period.of_year(frequency)
      |> Enum.map_reduce(Decimal.new(0), fn period, surplus ->
        output_vat = total(entries, :output, period)
        input_vat = total(entries, :input, period)
        refunded = total(entries, :refund, period)
        projected = Enum.filter(entries, &Projection.projected?/1)
        carried_over = surplus |> Decimal.sub(refunded) |> Decimal.max(0)
        balance = output_vat |> Decimal.sub(input_vat) |> Decimal.sub(carried_over)

        forecast = %{
          kind: :vat,
          period: period.key,
          period_start: period.first,
          period_end: period.last,
          amount: Decimal.max(balance, 0),
          due_date: Period.due_date(period, @due_day),
          description: gettext("VAT for %{period}", period: Period.name(period)),
          member_id: nil,
          details: %{
            output_vat: output_vat,
            input_vat: input_vat,
            projected_output_vat: total(projected, :output, period),
            projected_input_vat: total(projected, :input, period),
            carried_over: carried_over,
            refunded: refunded
          }
        }

        {forecast, balance |> Decimal.negate() |> Decimal.max(0)}
      end)

    forecasts
  end

  @doc """
  Splits a document's VAT between the days it was paid on, as cash accounting
  counts it (art. 21 ust. 1 of the VAT Act): each payment brings the VAT of the
  part of the gross amount it pays, and the unpaid part brings none yet.
  """
  @spec on_payment(Decimal.t(), Decimal.t(), [{Date.t(), Decimal.t()}]) :: [
          {Date.t(), Decimal.t()}
        ]
  def on_payment(vat, gross, payments) do
    {parts, _unpaid} =
      payments
      |> Enum.sort_by(&elem(&1, 0), Date)
      |> Enum.map_reduce(gross, fn {date, paid}, unpaid ->
        counted = Decimal.min(paid, unpaid)
        {{date, vat |> Decimal.mult(counted) |> Decimal.div(gross)}, Decimal.sub(unpaid, counted)}
      end)

    parts
  end

  defp total(entries, side, period) do
    entries
    |> Enum.filter(&(&1.side == side and &1.date in Date.range(period.first, period.last)))
    |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.amount, &2))
    |> Decimal.round(0, :half_up)
  end
end
