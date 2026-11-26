defmodule Firmowid.Taxes.Forecast.Detection do
  @moduledoc """
  Finds the settings of an owner that their real payments confirm, by asking
  the forecast calculators what each candidate setting would have made them pay.

  The evidence is an exact match, not a guess: a ZUS payment equals the
  contributions of `Firmowid.Taxes.Forecast.Zus` to the grosz, a lump-sum advance
  equals the advance of `Firmowid.Taxes.Forecast.Pit` within 1 zł (advances are
  rounded to a full złoty). The candidate that matches in most periods wins when
  that is at least two and no other candidate matches as often.

  Only the candidates a payment can tell apart are tried. `:start_relief` pays
  the same as `:none`, and `:small_plus` depends on figures Firmowid lacks, so
  neither is suggested; a payment they explain as well as the winner leaves the
  saved settings alone.
  """

  alias Firmowid.Taxes.Forecast.Income
  alias Firmowid.Taxes.Forecast.Pit
  alias Firmowid.Taxes.Forecast.Zus
  alias Firmowid.Taxes.Partner

  @minimum_matches 2

  # Social insurance and voluntary sickness, as the owner chooses them together.
  @zus_candidates [
    {:none, false},
    {:preferential, false},
    {:preferential, true},
    {:full, false},
    {:full, true}
  ]

  @type payment :: %{
          required(:amount) => Decimal.t(),
          required(:synced_at) => DateTime.t(),
          optional(atom()) => any()
        }

  @doc """
  Returns the social insurance and sickness that the ZUS `payments` (each with its
  booking `date`) confirm, with the payments of the months that match, or `nil`.

  The payments booked in a month pay the contributions of the month before, so
  January's, which pay the year before, are left out. `partner` holds the saved
  settings; its income tax form and `entries` decide the health contribution.
  """
  @spec zus([Income.entry()], Partner.t(), Decimal.t(), integer(), [payment()]) ::
          %{
            social_insurance: atom(),
            voluntary_sickness: boolean(),
            payments: [payment()]
          }
          | nil
  def zus(entries, partner, accident_rate, year, payments) do
    paid = payments |> Enum.reject(&(&1.date.month == 1)) |> Enum.group_by(& &1.date.month)

    score = fn {insurance, sickness} ->
      candidate = %{partner | social_insurance: insurance, voluntary_sickness: sickness}
      owed = owed_by_month(entries, candidate, accident_rate, year)

      matching = for {month, group} <- paid, matches?(total(group), owed[month - 1]), do: group
      {insurance, sickness, matching}
    end

    {_insurance, _sickness, saved} =
      score.({partner.social_insurance, partner.voluntary_sickness})

    with {insurance, sickness, matching} <- winner(Enum.map(@zus_candidates, score), &elem(&1, 2)),
         true <- length(matching) > length(saved) do
      %{
        social_insurance: insurance,
        voluntary_sickness: sickness,
        payments: List.flatten(matching)
      }
    else
      _unconfirmed -> nil
    end
  end

  @doc """
  Returns the lump-sum rate whose advances the `payments` confirm, with the
  payments of the periods that match, or `nil`. Each payment has the period it
  pays: `frequency` (`:monthly`, `:quarterly`) and its `number` in the year.

  `partner` holds the ZUS settings the contributions are computed from, which
  the advance deducts.
  """
  @spec lump_sum_rate([Income.entry()], Partner.t(), Decimal.t(), integer(), [payment()]) ::
          %{lump_sum_rate: Decimal.t(), payments: [payment()]} | nil
  def lump_sum_rate(entries, partner, accident_rate, year, payments) do
    contributions = Zus.contributions(entries, partner, accident_rate, year)
    paid = Enum.group_by(payments, &{&1.frequency, &1.number})
    frequencies = payments |> Enum.map(& &1.frequency) |> Enum.uniq()

    scored =
      for rate <- Partner.lump_sum_rates() do
        advances =
          for frequency <- frequencies,
              {advance, number} <-
                Enum.with_index(
                  advances(entries, partner, rate, frequency, contributions, year),
                  1
                ),
              into: %{},
              do: {{frequency, number}, advance}

        matching =
          for {period, group} <- paid, close?(total(group), advances[period]), do: group

        {rate, matching}
      end

    case winner(scored, &elem(&1, 1)) do
      {rate, matching} -> %{lump_sum_rate: rate, payments: List.flatten(matching)}
      nil -> nil
    end
  end

  # The contributions of each month of `year`, by the month number.
  defp owed_by_month(entries, partner, accident_rate, year) do
    entries
    |> Zus.contributions(partner, accident_rate, year)
    |> Zus.forecast(partner.member_id)
    |> Map.new(&{&1.period_start.month, &1.amount})
  end

  defp advances(entries, partner, rate, frequency, contributions, year) do
    candidate = %{partner | income_tax: :lump_sum, lump_sum_rate: rate, pit_advances: frequency}

    entries
    |> Pit.forecast(candidate, contributions, partner.member_id, year)
    |> Enum.map(& &1.amount)
  end

  # The candidate that matches in most periods, when at least two and alone.
  defp winner(scored, matching) do
    case Enum.sort_by(scored, &length(matching.(&1)), :desc) do
      [best, second | _rest] ->
        count = length(matching.(best))
        if count >= @minimum_matches and count > length(matching.(second)), do: best

      _fewer ->
        nil
    end
  end

  defp matches?(paid, owed), do: owed != nil and Decimal.eq?(paid, owed)

  defp close?(paid, advance),
    do: advance != nil and paid |> Decimal.sub(advance) |> Decimal.abs() |> Decimal.compare(1) != :gt

  defp total(payments), do: Enum.reduce(payments, Decimal.new(0), &Decimal.add(&1.amount, &2))
end
