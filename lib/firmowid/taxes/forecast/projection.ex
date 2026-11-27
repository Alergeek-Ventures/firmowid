defmodule Firmowid.Taxes.Forecast.Projection do
  @moduledoc """
  Projects the typical rest of the running period, and the periods ahead, onto the forecast entries.

  A period that is still running counts only the documents dated so far, so its
  amount is tiny early on and grows every day, and later ones count none. This
  module adds what they usually still bring, so the forecast tells the amount of
  the whole period:

    * for the rest of the current month, per side, the median over the three
      calendar months before it of what was dated after the same day of the
      month (a month shorter than today's day brings nothing);
    * for each whole month after it up to `until`, per side, the median
      monthly total of those three months.

  The median, not the average, so that one unusual month does not move the
  forecast of a business whose months are otherwise steady. For the same reason
  what comes in only one of the three months is not projected at all.

  With fewer than three months since the earliest entry the median is over the
  months that exist (of two, their mean), and with none nothing is projected.
  Refunds are never projected. Corrections in the history, being negative
  amounts, simply take part in the sums. A document already booked with a date
  after today is part of that typical rest, so it lowers the projection instead
  of adding to it.

  Why: checked against a company's past months in the middle of each month, the
  booked documents alone missed most of the month's total (a company that
  issues its invoices at the end of the month has booked nothing by then), a
  proportional extrapolation was no better for revenue, and the booked
  documents plus this typical rest came close.

  Limits: an estimate from the last three months only, so it misses a business
  that changed sharply in them, seasonality and one-off invoices. A company's
  first month has no history and counts only what is booked, so its forecast
  steps up once the second month starts.

  A projected entry is marked with `projected?: true`, one for each side and
  month, dated on the last day it covers, so the calculators can tell the booked
  part from the expected one.
  """

  @history_months 3

  @type entry :: %{
          required(:side) => atom(),
          required(:amount) => Decimal.t(),
          required(:date) => Date.t(),
          optional(:projected?) => boolean(),
          optional(atom()) => any()
        }

  @doc """
  Returns the projected entries of the days after `today` up to `until`, the
  last day of a month on or after the end of today's month, in today's year or a later one.
  """
  @spec project([entry()], Date.t(), Date.t()) :: [entry()]
  def project(entries, today, until) do
    entries = Enum.reject(entries, &(&1.side == :refund))
    months = history(entries, Date.beginning_of_month(today))

    for {side, side_entries} <- Enum.group_by(entries, & &1.side),
        {amount, date} <- projections(side_entries, months, today, until),
        not Decimal.eq?(amount, 0) do
      %{side: side, amount: amount, date: date, projected?: true}
    end
  end

  @doc "Whether the entry was projected and not read from a document."
  @spec projected?(map()) :: boolean()
  def projected?(entry), do: Map.get(entry, :projected?, false)

  # The first days of the up to three months before the current one, from the month of the earliest entry on.
  defp history([], _this_month), do: []

  defp history(entries, this_month) do
    earliest = entries |> Enum.map(& &1.date) |> Enum.min(Date) |> Date.beginning_of_month()

    for back <- 1..@history_months,
        month = Date.shift(this_month, month: -back),
        Date.compare(month, earliest) != :lt,
        do: month
  end

  defp projections(_entries, [], _today, _until), do: []

  defp projections(entries, months, today, until) do
    counted = Enum.filter(entries, &(Date.beginning_of_month(&1.date) in months))
    this_month_end = Date.end_of_month(today)

    rest =
      if today == this_month_end do
        []
      else
        typical = median(Enum.filter(counted, &(&1.date.day > today.day)), months)
        [{left(typical, entries, Date.add(today, 1), this_month_end), this_month_end}]
      end

    monthly = median(counted, months)

    later =
      for first <- later_months(Date.add(this_month_end, 1), until) do
        last = Date.end_of_month(first)
        {left(monthly, entries, first, last), last}
      end

    rest ++ later
  end

  # What is already booked for those days is part of the typical amount, not on top of it.
  defp left(typical, entries, first, last) do
    booked =
      entries
      |> Enum.filter(&(&1.date in Date.range(first, last)))
      |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.amount, &2))

    left = Decimal.sub(typical, booked)

    # More booked than usual leaves nothing to add; it never turns the projection around.
    if Decimal.positive?(typical), do: Decimal.max(left, 0), else: Decimal.min(left, 0)
  end

  defp later_months(first, until) do
    first
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(Date.end_of_month(&1), until) != :gt))
  end

  # Each history month brings one value, its sum (zero without entries).
  defp median(entries, months) do
    sums = Enum.group_by(entries, &Date.beginning_of_month(&1.date), & &1.amount)

    sorted =
      months
      |> Enum.map(fn month ->
        sums |> Map.get(month, []) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      end)
      |> Enum.sort(Decimal)

    Decimal.round(middle(sorted), 2, :half_up)
  end

  defp middle(sorted) do
    half = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1 do
      Enum.at(sorted, half)
    else
      Decimal.div(Decimal.add(Enum.at(sorted, half - 1), Enum.at(sorted, half)), 2)
    end
  end
end
