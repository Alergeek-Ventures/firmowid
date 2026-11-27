defmodule Firmowid.Taxes.Forecast.PaymentHistory do
  @moduledoc """
  Falls back to what the company actually paid when its documents are evidently incomplete.

  Some companies do not issue their sales invoices in Firmowid, so the documents give a VAT or PIT
  forecast of zero although the company pays these taxes every month. The fallback applies to a
  group of forecasts (the same kind, member and frequency) only when the documents explained less
  than half of what was paid: the reference periods are the three latest periods of the group's
  frequency whose due date is before today, `paid` is the sum paid for each of them (see
  `Firmowid.Taxes.Forecast.Payments`; zero when none) and the documents' amount of a reference
  period is the amount of its reference forecast, an unadjusted forecast of the same kind, member
  and period. The group is left alone when a reference period has no reference forecast, when the
  typical payment (the median of the three sums paid) is zero, or when the three reference
  forecasts add up to at least half of the three sums paid. A tax-scale PIT of January to March,
  a ZUS that drops in January or a CIT advance after a loss are low for a reason the documents
  explain, so they are not touched.

  In an active group a forecast that is not past due, whose period starts within the horizon of
  `Firmowid.Taxes.Forecast.Period.horizon/1` and whose amount is less than half of the typical
  payment gets the typical payment as its amount, and its `details` get `documents_amount` (what
  the documents gave) and `typical_payment`. Every other forecast stays as it is. A period beyond
  the horizon is not projected either, so its low amount tells nothing about the documents.

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

  @doc """
  Returns `forecasts` with the amounts that fall far short of the typical payment replaced by it.

  `reference` lists unadjusted forecasts that should cover the reference periods of `forecasts`
  (see `reference_years/2`); it may include `forecasts` themselves.
  """
  @spec adjust([map()], [map()], [Payments.payment()], Date.t()) :: [map()]
  def adjust(forecasts, reference, payments, today) do
    sums =
      payments
      |> Enum.group_by(&{&1.kind, &1.period}, & &1.amount)
      |> Map.new(fn {key, amounts} -> {key, sum(amounts)} end)

    documents = Map.new(reference, &{{&1.kind, &1.member_id, &1.period}, &1.amount})

    typical =
      forecasts
      |> Enum.map(&group/1)
      |> Enum.uniq()
      |> Map.new(&{&1, typical_payment(&1, sums, documents, today)})

    Enum.map(forecasts, &adjust_forecast(&1, typical[group(&1)], today))
  end

  @doc "Returns the calendar years the reference periods of `forecasts` fall in."
  @spec reference_years([map()], Date.t()) :: [integer()]
  def reference_years(forecasts, today) do
    forecasts
    |> Enum.map(&group/1)
    |> Enum.uniq()
    |> Enum.flat_map(&reference_periods(&1, today))
    |> Enum.map(& &1.last.year)
    |> Enum.uniq()
  end

  defp adjust_forecast(forecast, typical, today) do
    if typical != nil and not Date.before?(forecast.due_date, today) and
         not Date.after?(forecast.period_start, Period.horizon(today)) and
         Decimal.compare(forecast.amount, Decimal.div(typical, 2)) == :lt do
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

  defp group(%{kind: kind, member_id: member_id, period: period}),
    do: {kind, member_id, if(String.contains?(period, "-Q"), do: :quarterly, else: :monthly)}

  # The periods of the year before and of this one cover the three latest ones due before today.
  defp reference_periods({kind, _member_id, frequency}, today) do
    day = due_day(kind)

    [today.year - 1, today.year]
    |> Enum.flat_map(&Period.of_year(&1, frequency))
    |> Enum.filter(&Date.before?(Period.due_date(&1, day), today))
    |> Enum.take(-@reference_periods)
  end

  # Nil when the group is left alone.
  defp typical_payment({kind, member_id, _frequency} = group, sums, documents, today) do
    periods = reference_periods(group, today)
    paid = Enum.map(periods, &Map.get(sums, {kind, &1.key}, Decimal.new(0)))
    explained = Enum.map(periods, &Map.get(documents, {kind, member_id, &1.key}))
    [_lowest, typical, _highest] = Enum.sort(paid, Decimal)

    if not Enum.member?(explained, nil) and Decimal.compare(typical, 0) == :gt and
         Decimal.compare(sum(explained), Decimal.div(sum(paid), 2)) == :lt,
       do: typical
  end

  defp sum(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)

  defp due_day(:vat), do: Vat.due_day()
  defp due_day(:cit), do: Cit.due_day()
  defp due_day(:pit), do: Pit.due_day()
  defp due_day(:zus), do: Zus.due_day()
end
