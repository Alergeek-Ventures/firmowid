defmodule Firmowid.Delegations.PerDiem do
  @moduledoc """
  Calculates statutory per diems and lump sums for business trips.

  Domestic trips follow §§ 7–9 and foreign trips §§ 13, 14, 16 and 17 of the regulation on
  business-trip allowances (Dz.U. 2023 poz. 2190). The time spent in Poland on the way to
  and from a foreign destination is a domestic trip (§ 21). Provided meals reduce the per
  diem by a fixed share of the daily rate each.

  On a foreign trip, nights without a receipt and local transport count as abroad, and
  every amount in the destination currency is converted to PLN with the NBP rate stored
  when the delegation was approved.
  """

  alias Firmowid.Delegations.PerDiemRates

  @type kind ::
          :domestic_per_diem
          | :foreign_per_diem
          | :accommodation_lump_sum
          | :local_transport_lump_sum
          | :station_transfer_lump_sum

  @type line :: %{kind: kind(), amount: Money.t(), foreign_amount: Money.t() | nil}

  @type t :: %{
          lines: [line()],
          per_diem: Money.t(),
          lump_sums: Money.t(),
          total: Money.t()
        }

  @per_diem_kinds [:domestic_per_diem, :foreign_per_diem]

  @hour 60 * 60
  @day 24 * @hour

  # Each provided meal deducts a share of the daily rate (§ 7 ust. 4, § 14 ust. 2). Abroad,
  # even free full board leaves 25% of the per diem (§ 14 ust. 1), so fewer meals never
  # leave less; at home full board leaves nothing (§ 7 ust. 3 pkt 2).
  @domestic_meals %{shares: %{breakfasts: "0.25", lunches: "0.5", dinners: "0.25"}, minimum: "0"}
  @foreign_meals %{shares: %{breakfasts: "0.15", lunches: "0.3", dinners: "0.3"}, minimum: "0.25"}
  @no_meals %{breakfasts: 0, lunches: 0, dinners: 0}

  @doc """
  Calculates the per diem and lump sums for a delegation, or returns `nil` until its trip
  times are complete and in order.

  Lines always include the per diems; a lump sum appears only when it is claimed.
  """
  @spec for_delegation(map()) :: t() | nil
  def for_delegation(%{destination_country: "PL"} = delegation) do
    with [started_at, ended_at] <-
           ordered_times([delegation.trip_started_at, delegation.trip_ended_at]) do
      duration = NaiveDateTime.diff(ended_at, started_at)
      rate = PerDiemRates.domestic_per_diem()

      summarize([
        line(
          :domestic_per_diem,
          amount(rate, domestic_days(duration), meals(delegation), @domestic_meals)
        ),
        # § 8 ust. 3
        line(:accommodation_lump_sum, share(rate, "1.5", delegation.lump_sum_nights)),
        # § 9 ust. 1
        line(:local_transport_lump_sum, local_transport(delegation, rate, "0.2", duration))
      ])
    end
  end

  def for_delegation(delegation) do
    times = [
      delegation.trip_started_at,
      delegation.abroad_started_at,
      delegation.abroad_ended_at,
      delegation.trip_ended_at
    ]

    with %Decimal{} = nbp_rate <- delegation.per_diem_nbp_rate,
         [started_at, abroad_started_at, abroad_ended_at, ended_at] <- ordered_times(times) do
      domestic_duration =
        NaiveDateTime.diff(abroad_started_at, started_at) +
          NaiveDateTime.diff(ended_at, abroad_ended_at)

      abroad_duration = NaiveDateTime.diff(abroad_ended_at, abroad_started_at)
      rates = PerDiemRates.foreign(delegation.destination_country)

      abroad_days =
        Decimal.add(div(abroad_duration, @day), foreign_partial_day(rem(abroad_duration, @day)))

      summarize([
        line(
          :domestic_per_diem,
          amount(
            PerDiemRates.domestic_per_diem(),
            domestic_days(domestic_duration),
            @no_meals,
            @domestic_meals
          )
        ),
        foreign_line(
          :foreign_per_diem,
          amount(rates.per_diem, abroad_days, meals(delegation), @foreign_meals),
          nbp_rate
        ),
        # § 16 ust. 2
        foreign_line(
          :accommodation_lump_sum,
          share(rates.accommodation_limit, "0.25", delegation.lump_sum_nights),
          nbp_rate
        ),
        # § 17 ust. 3
        foreign_line(
          :local_transport_lump_sum,
          local_transport(delegation, rates.per_diem, "0.1", abroad_duration),
          nbp_rate
        ),
        # § 17 ust. 1 and 2: a transfer both ways is one per diem, one way half of it.
        foreign_line(
          :station_transfer_lump_sum,
          share(rates.per_diem, "0.5", delegation.station_transfers),
          nbp_rate
        )
      ])
    end
  end

  defp meals(delegation) do
    %{
      breakfasts: delegation.provided_breakfasts,
      lunches: delegation.provided_lunches,
      dinners: delegation.provided_dinners
    }
  end

  defp ordered_times(times) do
    if Enum.all?(times, & &1) and times == Enum.sort(times, NaiveDateTime), do: times
  end

  defp line(kind, amount), do: %{kind: kind, amount: amount, foreign_amount: nil}

  defp foreign_line(kind, foreign_amount, nbp_rate) do
    amount =
      :PLN
      |> Money.new(Decimal.mult(Money.to_decimal(foreign_amount), nbp_rate))
      |> round_half_up()

    %{kind: kind, amount: amount, foreign_amount: foreign_amount}
  end

  defp summarize(lines) do
    lines = Enum.reject(lines, &(&1.kind not in @per_diem_kinds and Money.zero?(&1.amount)))
    {per_diem, lump_sums} = Enum.split_with(lines, &(&1.kind in @per_diem_kinds))

    %{
      lines: lines,
      per_diem: sum(per_diem),
      lump_sums: sum(lump_sums),
      total: sum(lines)
    }
  end

  defp sum(lines), do: Enum.reduce(lines, Money.new(:PLN, 0), &Money.add!(&2, &1.amount))

  # Lump sums for local transport are due for every started day of the stay.
  defp local_transport(%{local_transport_lump_sum: true}, rate, share, duration),
    do: share(rate, share, ceil(duration / @day))

  defp local_transport(_delegation, rate, _share, _duration), do: Money.zero(rate)

  # Payroll rounds half a grosz up, unlike Money's default banker's rounding.
  defp round_half_up(money), do: Money.round(money, rounding_mode: :half_up)

  defp share(rate, share, count), do: rate |> Money.mult!(Decimal.mult(share, count)) |> round_half_up()

  # § 7 ust. 2 pkt 1: a trip of up to one day counts by its length.
  defp domestic_days(duration) when duration < 8 * @hour, do: Decimal.new(0)
  defp domestic_days(duration) when duration <= 12 * @hour, do: Decimal.new("0.5")
  defp domestic_days(duration) when duration <= @day, do: Decimal.new(1)

  # § 7 ust. 2 pkt 2: a longer trip adds its last started day.
  defp domestic_days(duration) do
    partial_day =
      case rem(duration, @day) do
        0 -> Decimal.new(0)
        remainder when remainder <= 8 * @hour -> Decimal.new("0.5")
        _remainder -> Decimal.new(1)
      end

    Decimal.add(div(duration, @day), partial_day)
  end

  # § 13 ust. 3 pkt 2
  defp foreign_partial_day(0), do: Decimal.new(0)
  defp foreign_partial_day(remainder) when remainder <= 8 * @hour, do: Decimal.div(1, 3)
  defp foreign_partial_day(remainder) when remainder <= 12 * @hour, do: Decimal.new("0.5")
  defp foreign_partial_day(_remainder), do: Decimal.new(1)

  defp amount(daily_rate, days, meals, rules) do
    meal_days =
      Enum.reduce(rules.shares, Decimal.new(0), fn {meal, share}, total ->
        Decimal.add(total, Decimal.mult(Map.fetch!(meals, meal), share))
      end)

    days
    |> Decimal.sub(meal_days)
    |> Decimal.max(Decimal.mult(days, rules.minimum))
    |> then(&Money.mult!(daily_rate, &1))
    |> round_half_up()
  end
end
