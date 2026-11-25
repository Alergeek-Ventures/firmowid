defmodule Firmowid.Taxes.Forecast.PitTest do
  use ExUnit.Case, async: true

  alias Firmowid.Taxes.Forecast.Period
  alias Firmowid.Taxes.Forecast.Pit

  @member_id "01990000-0000-7000-8000-000000000001"

  defp revenue(date, amount), do: %{side: :revenue, amount: Decimal.new(amount), date: date}
  defp cost(date, amount), do: %{side: :cost, amount: Decimal.new(amount), date: date}

  # The monthly contributions as `Zus.contributions/4` returns them, reduced to what PIT deducts.
  defp contributions(social, health) do
    for period <- Period.of_year(2026, :monthly) do
      %{period: period, social_deductible: Decimal.new(social), health: Decimal.new(health)}
    end
  end

  defp forecast(entries, partner, contributions) do
    partner =
      Map.merge(%{income_tax: :tax_scale, lump_sum_rate: nil, pit_advances: :monthly}, partner)

    Pit.forecast(entries, partner, contributions, @member_id, 2026)
  end

  defp amounts(forecasts), do: Enum.map(forecasts, &Decimal.to_integer(&1.amount))

  test "the tax scale deducts the social contributions and its second bracket starts at 120 000 zł" do
    entries = [revenue(~D[2026-01-10], "40000"), revenue(~D[2026-03-10], "100000")]

    forecasts = forecast(entries, %{}, contributions("1000", "500"))

    # January: (40 000 - 1 000) * 12% - 3 600. February's cumulative tax is lower, so nothing is
    # owed. March: 140 000 - 3 000 = 137 000, 10 800 + 32% of 17 000 = 16 240, less January's 1 080.
    assert [1080, 0, 15_160 | _] = amounts(forecasts)

    january = hd(forecasts)
    assert %{kind: :pit, period: "2026-01", member_id: @member_id} = january
    assert Decimal.equal?(january.details.social_deducted, 1000)
    assert Decimal.equal?(january.details.health_deducted, 0)
    assert Decimal.equal?(january.details.tax_base, 39_000)
    assert Decimal.equal?(january.details.tax, 1080)
    assert january.details.rates_year == 2026

    march = Enum.at(forecasts, 2)
    assert Decimal.equal?(march.details.tax_base, 137_000)
    assert Decimal.equal?(march.details.tax, 16_240)
    assert Decimal.equal?(march.details.advances_before, 1080)
  end

  test "the flat tax deducts the health contributions up to the yearly limit" do
    forecasts =
      forecast(
        [revenue(~D[2026-01-10], "100000")],
        %{income_tax: :flat_tax},
        contributions("1000", "1500")
      )

    # January: (100 000 - 1 000 - 1 500) * 19%.
    january = hd(forecasts)
    assert Decimal.equal?(january.amount, 18_525)
    assert Decimal.equal?(january.details.health_deducted, 1500)

    # Nine months of health contributions are 13 500, ten would be 15 000 and only 14 100 counts.
    assert Decimal.equal?(Enum.at(forecasts, 8).details.health_deducted, 13_500)

    october = Enum.at(forecasts, 9)
    assert Decimal.equal?(october.details.health_deducted, 14_100)
    assert Decimal.equal?(october.details.tax_base, 75_900)
    assert Decimal.equal?(october.details.tax, 14_421)
    assert Decimal.equal?(october.details.rate, 19)
  end

  test "the lump sum taxes the revenue less the social and half of the health contributions" do
    entries = [revenue(~D[2026-01-10], "100000"), cost(~D[2026-01-12], "30000")]

    january =
      entries
      |> forecast(
        %{income_tax: :lump_sum, lump_sum_rate: Decimal.new("8.5")},
        contributions("1000", "1500")
      )
      |> hd()

    # 100 000 - 1 000 - 750 = 98 250 at 8.5% is 8 351.25; the costs do not count.
    assert Decimal.equal?(january.details.tax_base, 98_250)
    assert Decimal.equal?(january.amount, 8351)
    assert Decimal.equal?(january.details.health_deducted, 750)
    assert Decimal.equal?(january.details.rate, "8.5")
  end

  test "quarterly advances follow the quarters, the last one due on 20 January" do
    entries = [revenue(~D[2026-02-10], "40000"), revenue(~D[2026-11-10], "40000")]

    forecasts = forecast(entries, %{pit_advances: :quarterly}, contributions("1000", "0"))

    # Q1: 37 000 * 12% - 3 600; Q2: 34 000 taxes less, nothing is owed; Q4: 68 000 * 12% - 3 600
    # less the 840 of Q1.
    assert [840, 0, 0, 3720] = amounts(forecasts)
    assert Enum.map(forecasts, & &1.period) == ["2026-Q1", "2026-Q2", "2026-Q3", "2026-Q4"]
    assert Enum.at(forecasts, 0).due_date == ~D[2026-04-20]
    assert List.last(forecasts).due_date == ~D[2027-01-20]
  end

  test "an advance is never negative after a loss, and a later profit is taxed only beyond what was paid" do
    entries = [
      revenue(~D[2026-01-10], "100000"),
      cost(~D[2026-02-10], "150000"),
      revenue(~D[2026-03-10], "200000")
    ]

    forecasts = forecast(entries, %{income_tax: :flat_tax}, contributions("0", "0"))

    # January 19 000; February's cumulative income of -50 000 owes nothing; March's 150 000 owes
    # 28 500, less the 19 000 paid.
    assert [19_000, 0, 9500, 0 | _] = amounts(forecasts)
    assert Decimal.equal?(Enum.at(forecasts, 1).details.tax_base, 0)
    assert Decimal.equal?(Enum.at(forecasts, 2).details.tax, 28_500)
    assert Decimal.equal?(Enum.at(forecasts, 2).details.advances_before, 19_000)
    assert Decimal.equal?(Enum.at(forecasts, 3).details.advances_before, 28_500)
    assert List.last(forecasts).due_date == ~D[2027-01-20]
  end
end
