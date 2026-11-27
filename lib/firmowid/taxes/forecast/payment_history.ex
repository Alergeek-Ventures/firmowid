defmodule Firmowid.Taxes.Forecast.PaymentHistory do
  @moduledoc """
  Corrects the forecast with what the company actually paid, and forecasts from it the kinds the
  settings do not cover.

  Some companies do not issue their sales invoices in Firmowid, so the documents give a VAT or PIT
  forecast of zero although the company pays these taxes every month; wrong settings can as well
  give an amount far above what is paid. A group of forecasts is the same kind, member and
  frequency. Its reference periods are the three latest periods of the group's frequency whose due
  date is before today and which the bank history covers: the history starts on the booking date
  of the organization's earliest transaction (`history_start`), and a period is known when its due
  date is on or after that day, so a company connected 90 days ago, or one that pays quarterly,
  has fewer than three reference periods, one or none. `paid` is the sum paid for each of them (see
  `Firmowid.Taxes.Forecast.Payments`; zero when none, a zero inside the history counts) and the
  documents' amount of a reference period is the amount of its reference forecast, an unadjusted
  forecast of the same kind, member and period. The typical payment is the median of the sums paid
  for the known reference periods (the mean of two, the sum of one); without a known period it is
  zero.

  Amounts are compared with a tolerance of 1.5: `a` is close to `b` when it lies within
  `b / 1.5` to `b * 1.5`. The documents track the payments of a group when the three reference
  forecasts of the known reference periods add up to an amount close to their sums paid; such a group is never touched, so a
  tax-scale PIT of January to March, a ZUS that drops in January or a CIT advance after a loss,
  which the documents explain, stay as computed. Otherwise the group is active, unless a known reference
  period has no reference forecast or the typical payment is zero. The payments of an owner's PIT
  and ZUS (a group with a member) count only for a sole proprietorship with exactly one partner;
  with several owners they cannot be attributed.

  In an active group a forecast that is not past due, whose period starts within the horizon of
  `Firmowid.Taxes.Forecast.Period.horizon/1` and whose amount is not close to the typical payment,
  below or above it, gets the typical payment as its amount, and its `details` get
  `documents_amount` (what the documents gave) and `typical_payment`. Every other forecast stays as
  it is. A period beyond the horizon is not projected either, so its low amount tells nothing about
  the documents.

  A kind (VAT, CIT, PIT or ZUS) of which the settings gave no forecast at all in the year is
  forecast from the payments alone, as the organization's totals, whoever paid them: with the
  frequency of its latest paid period, the typical payment of the known ones among the three latest periods due before
  today (none when it is zero) and one forecast for each period of the year that is not past due,
  starts within the horizon and has no payment yet. Its `details` have only `typical_payment`. A
  limited company's ZUS is due on the 15th, as a payer with legal personality pays by then (see
  `Firmowid.Taxes.Forecast.Zus.payer_due_day/1`).

  Limits: a payment is matched to a period by its title (a ZUS payment by its booking month), so a
  payment of another period under a wrong title, or paid late, lands in the wrong one.
  """
  alias Firmowid.Taxes.Forecast.Cit
  alias Firmowid.Taxes.Forecast.Payments
  alias Firmowid.Taxes.Forecast.Period
  alias Firmowid.Taxes.Forecast.Pit
  alias Firmowid.Taxes.Forecast.Vat
  alias Firmowid.Taxes.Forecast.Zus

  @reference_periods 3
  @tolerance Decimal.new("1.5")
  @kinds [:vat, :cit, :pit, :zus]

  @doc """
  Returns `forecasts` with the amounts that are not close to the typical payment replaced by it,
  and the forecasts from the payments of the kinds `forecasts` lack, in the order VAT, CIT, PIT, ZUS.

  `reference` lists unadjusted forecasts that should cover the reference periods of `forecasts`
  (see `reference_years/2`); it may include `forecasts` themselves. The options are the `year` of
  the forecasts, the `legal_form` of the organization, `owner_pays?`, whether an owner's
  payments are known (a sole proprietorship with one partner), and the `history_start`, the day
  the bank history starts.
  """
  @spec adjust([map()], [map()], [Payments.payment()], Date.t(), keyword()) :: [map()]
  def adjust(forecasts, reference, payments, today, opts) do
    sums =
      payments
      |> Enum.group_by(&{&1.kind, &1.period}, & &1.amount)
      |> Map.new(fn {key, amounts} -> {key, sum(amounts)} end)

    documents = Map.new(reference, &{{&1.kind, &1.member_id, &1.period}, &1.amount})

    typical =
      forecasts
      |> Enum.map(&group/1)
      |> Enum.uniq()
      |> Map.new(&{&1, typical_payment(&1, sums, documents, today, opts)})

    adjusted = Enum.map(forecasts, &adjust_forecast(&1, typical[group(&1)], today))
    covered = Enum.map(forecasts, & &1.kind)

    from_payments =
      for kind <- @kinds -- covered,
          forecast <- from_payments(kind, payments, sums, today, opts),
          do: forecast

    Enum.sort_by(
      adjusted ++ from_payments,
      &Enum.find_index(@kinds, fn kind -> kind == &1.kind end)
    )
  end

  @doc """
  Returns the calendar years the three latest periods before today of `forecasts` fall in, which
  include those of the reference periods.
  """
  @spec reference_years([map()], Date.t()) :: [integer()]
  def reference_years(forecasts, today) do
    forecasts
    |> Enum.map(&group/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn {kind, _member_id, frequency} ->
      latest_periods(kind, frequency, today, nil)
    end)
    |> Enum.map(& &1.last.year)
    |> Enum.uniq()
  end

  defp adjust_forecast(forecast, typical, today) do
    if typical != nil and not Date.before?(forecast.due_date, today) and
         not Date.after?(forecast.period_start, Period.horizon(today)) and
         not close?(forecast.amount, typical) do
      %{
        forecast
        | amount: typical,
          details:
            Map.merge(forecast.details, %{
              documents_amount: forecast.amount,
              typical_payment: typical
            })
      }
    else
      forecast
    end
  end

  defp group(%{kind: kind, member_id: member_id, period: period}), do: {kind, member_id, frequency(period)}

  defp frequency(period), do: if(String.contains?(period, "-Q"), do: :quarterly, else: :monthly)

  # The periods of the year before and of this one cover the three latest ones due before today.
  # `legal_form` decides the due day of ZUS.
  defp latest_periods(kind, frequency, today, legal_form) do
    day = due_day(kind, legal_form)

    [today.year - 1, today.year]
    |> Enum.flat_map(&Period.of_year(&1, frequency))
    |> Enum.filter(&Date.before?(Period.due_date(&1, day), today))
    |> Enum.take(-@reference_periods)
  end

  # Those of the latest periods that the bank history covers: due on or after its start.
  defp reference_periods(kind, frequency, today, opts) do
    day = due_day(kind, opts[:legal_form])

    kind
    |> latest_periods(frequency, today, opts[:legal_form])
    |> Enum.reject(&Date.before?(Period.due_date(&1, day), opts[:history_start]))
  end

  # Nil when the group is left alone.
  defp typical_payment({kind, member_id, frequency}, sums, documents, today, opts) do
    periods = reference_periods(kind, frequency, today, opts)
    paid = paid(kind, periods, sums)
    explained = Enum.map(periods, &Map.get(documents, {kind, member_id, &1.key}))
    typical = median(paid)

    if (member_id == nil or opts[:owner_pays?]) and not Enum.member?(explained, nil) and
         Decimal.compare(typical, 0) == :gt and not close?(sum(explained), sum(paid)),
       do: typical
  end

  defp from_payments(kind, payments, sums, today, opts) do
    case latest_frequency(kind, payments) do
      nil ->
        []

      frequency ->
        typical = kind |> paid(reference_periods(kind, frequency, today, opts), sums) |> median()
        day = due_day(kind, opts[:legal_form])

        for period <- Period.of_year(opts[:year], frequency),
            Decimal.compare(typical, 0) == :gt,
            not is_map_key(sums, {kind, period.key}),
            due_date = Period.due_date(period, day),
            not Date.before?(due_date, today),
            not Date.after?(period.first, Period.horizon(today)) do
          %{
            kind: kind,
            period: period.key,
            period_start: period.first,
            period_end: period.last,
            amount: typical,
            due_date: due_date,
            description: description(kind, period),
            member_id: nil,
            details: %{typical_payment: typical}
          }
        end
    end
  end

  # The frequency of the period that ended last among those the kind was paid for.
  defp latest_frequency(kind, payments) do
    case for(%{kind: ^kind, period: period} <- payments, do: period) do
      [] -> nil
      periods -> periods |> Enum.max_by(&last_month/1) |> frequency()
    end
  end

  defp last_month(<<year::binary-size(4), "-Q", quarter::binary>>), do: {year, String.to_integer(quarter) * 3}

  defp last_month(<<year::binary-size(4), "-", month::binary>>), do: {year, String.to_integer(month)}

  defp paid(kind, periods, sums), do: Enum.map(periods, &Map.get(sums, {kind, &1.key}, Decimal.new(0)))

  # Zero without a period.
  defp median([]), do: Decimal.new(0)

  defp median(paid) do
    sorted = Enum.sort(paid, Decimal)
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1,
      do: Enum.at(sorted, middle),
      else: sorted |> Enum.slice(middle - 1, 2) |> sum() |> Decimal.div(2)
  end

  # Whether `amount` lies within `reference / 1.5` to `reference * 1.5`.
  defp close?(amount, reference) do
    Decimal.compare(Decimal.mult(amount, @tolerance), reference) != :lt and
      Decimal.compare(amount, Decimal.mult(reference, @tolerance)) != :gt
  end

  defp sum(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)

  defp due_day(:vat, _legal_form), do: Vat.due_day()
  defp due_day(:cit, _legal_form), do: Cit.due_day()
  defp due_day(:pit, _legal_form), do: Pit.due_day()
  defp due_day(:zus, legal_form), do: Zus.payer_due_day(legal_form)

  defp description(:vat, period), do: Vat.description(period)
  defp description(:cit, period), do: Cit.description(period)
  defp description(:pit, period), do: Pit.description(period)
  defp description(:zus, period), do: Zus.description(period)
end
