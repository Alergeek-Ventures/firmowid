defmodule Firmowid.Taxes.Forecast.Period do
  @moduledoc """
  The settlement periods of a calendar year, months or quarters, and the day a
  payment for one is due.

  A period's `key` is stable (`2026-10`, `2026-Q3`), so a forecast can be found
  again when it is recalculated.
  """
  use Gettext, backend: Firmowid.Gettext

  # How many months after today's the forecast looks ahead, to the end of that month.
  @horizon_months 2

  @type frequency :: :monthly | :quarterly
  @type t :: %{key: String.t(), first: Date.t(), last: Date.t()}

  @doc "Returns the year's periods in order."
  @spec of_year(integer(), frequency()) :: [t()]
  def of_year(year, :monthly) do
    for month <- 1..12 do
      first = Date.new!(year, month, 1)

      %{
        key: "#{year}-#{String.pad_leading("#{month}", 2, "0")}",
        first: first,
        last: Date.end_of_month(first)
      }
    end
  end

  def of_year(year, :quarterly) do
    for quarter <- 1..4 do
      %{
        key: "#{year}-Q#{quarter}",
        first: Date.new!(year, quarter * 3 - 2, 1),
        last: Date.end_of_month(Date.new!(year, quarter * 3, 1))
      }
    end
  end

  @doc "Returns the last day of the month or the quarter of `frequency` that contains `date`."
  @spec last_day(frequency(), Date.t()) :: Date.t()
  def last_day(:monthly, date), do: Date.end_of_month(date)

  def last_day(:quarterly, date), do: Date.end_of_month(Date.new!(date.year, div(date.month - 1, 3) * 3 + 3, 1))

  @doc """
  Returns the last day the forecast looks ahead to: the end of the second month after today's.
  A period is within the horizon when it starts on or before that day.
  """
  @spec horizon(Date.t()) :: Date.t()
  def horizon(today), do: Date.end_of_month(Date.shift(today, month: @horizon_months))

  @doc "Returns the period's name for a description, such as `10/2026`."
  @spec name(t()) :: String.t()
  def name(%{first: %Date{month: month, year: year}, last: %Date{month: month}}),
    do: "#{String.pad_leading("#{month}", 2, "0")}/#{year}"

  def name(%{last: %Date{month: month, year: year}}),
    do: gettext("quarter %{quarter} of %{year}", quarter: div(month, 3), year: year)

  @doc """
  Returns the `day` of the month after the period, moved from a Saturday or a
  public holiday to the next working day (art. 12 § 5 of the Tax Ordinance).
  """
  @spec due_date(t(), 1..28) :: Date.t()
  def due_date(%{last: last}, day), do: next_working_day(%{Date.add(last, 1) | day: day})

  defp next_working_day(date) do
    if Date.day_of_week(date) in [6, 7] or date in holidays(date.year),
      do: next_working_day(Date.add(date, 1)),
      else: date
  end

  # The days off of the act of 18 January 1951 that may fall on a weekday; the Christmas Eve
  # since 2025. Easter Monday and Corpus Christi follow Easter Sunday by 1 and 60 days.
  defp holidays(year) do
    easter = easter_sunday(year)

    fixed =
      for {month, day} <- [
            {1, 1},
            {1, 6},
            {5, 1},
            {5, 3},
            {8, 15},
            {11, 1},
            {11, 11},
            {12, 25},
            {12, 26}
          ],
          do: Date.new!(year, month, day)

    christmas_eve = if year >= 2025, do: [Date.new!(year, 12, 24)], else: []

    [Date.add(easter, 1), Date.add(easter, 60)] ++ fixed ++ christmas_eve
  end

  # The anonymous Gregorian algorithm (Meeus, Jones, Butcher).
  defp easter_sunday(year) do
    a = rem(year, 19)
    b = div(year, 100)
    c = rem(year, 100)
    h = rem(19 * a + b - div(b, 4) - div(b - div(b + 8, 25) + 1, 3) + 15, 30)
    l = rem(32 + 2 * rem(b, 4) + 2 * div(c, 4) - h - rem(c, 4), 7)
    m = div(a + 11 * h + 22 * l, 451)
    month = div(h + l - 7 * m + 114, 31)

    Date.new!(year, month, rem(h + l - 7 * m + 114, 31) + 1)
  end
end
