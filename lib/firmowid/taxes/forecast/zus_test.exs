defmodule Firmowid.Taxes.Forecast.ZusTest do
  use ExUnit.Case, async: true

  alias Firmowid.Taxes.Forecast.Zus

  @member_id "01990000-0000-7000-8000-000000000001"

  defp revenue(date, amount), do: %{side: :revenue, amount: Decimal.new(amount), date: date}
  defp cost(date, amount), do: %{side: :cost, amount: Decimal.new(amount), date: date}

  defp forecasts(entries \\ [], overrides \\ %{}) do
    partner =
      Map.merge(
        %{
          profit_share: Decimal.new(100),
          income_tax: :tax_scale,
          social_insurance: :full,
          voluntary_sickness: false
        },
        overrides
      )

    entries
    |> Zus.contributions(partner, Decimal.new("1.67"), 2026)
    |> Zus.forecast(@member_id)
  end

  defp social(%{details: details}) do
    [:pension, :disability, :accident, :sickness, :labour_fund]
    |> Enum.map(&Map.fetch!(details, &1))
    |> Enum.reduce(&Decimal.add/2)
  end

  defp assert_amount(amount, expected), do: assert(Decimal.equal?(amount, expected), "#{amount} is not #{expected}")

  test "full and preferential contributions match the ZUS table, with the Labour Fund only from the minimum wage" do
    [january | _] = forecasts([], %{voluntary_sickness: true})
    assert_amount(social(january), "1926.76")
    assert_amount(january.details.labour_fund, "138.47")

    assert_amount(social(hd(forecasts())), "1788.29")

    [preferential | _] =
      forecasts([], %{social_insurance: :preferential, voluntary_sickness: true})

    assert_amount(social(preferential), "456.18")
    assert_amount(preferential.details.labour_fund, 0)

    assert_amount(social(hd(forecasts([], %{social_insurance: :preferential}))), "420.86")
  end

  test "a forecast is one per month, due on the 20th of the next month, with the health minimum of the month" do
    forecasts = forecasts([], %{voluntary_sickness: true})

    assert length(forecasts) == 12

    assert [%{kind: :zus, period: "2026-01", member_id: @member_id} = january, february | _] =
             forecasts

    assert january.due_date == ~D[2026-02-20]
    assert february.due_date == ~D[2026-03-20]
    assert List.last(forecasts).due_date == ~D[2027-01-20]
    assert january.details.rates_year == 2026

    assert_amount(january.amount, "2241.72")
    assert_amount(february.amount, "2359.30")
  end

  test "start relief and no insurance pay the health contribution only" do
    for insurance <- [:start_relief, :none] do
      [january, february | _] = forecasts([], %{social_insurance: insurance})

      assert_amount(social(january), 0)
      assert_amount(january.amount, "314.96")
      assert_amount(february.amount, "432.54")
    end
  end

  test "health is a percent of the previous month's income less the social contributions, at least the minimum" do
    entries = [
      revenue(~D[2025-12-10], "10000"),
      revenue(~D[2026-01-10], "10000"),
      cost(~D[2026-01-20], "2000")
    ]

    # Social contributions of a month: 1 649.82 without sickness.
    [january, february, march | _] = forecasts(entries)
    assert_amount(january.details.health, "751.52")
    assert_amount(january.details.health_base, "8350.18")
    assert_amount(february.details.health, "571.52")
    assert_amount(march.details.health, "432.54")
    assert_amount(march.details.health_base, 0)

    # 4.9%: 409.16 is above the January minimum, 311.16 below the February one.
    [january, february | _] = forecasts(entries, %{income_tax: :flat_tax})
    assert_amount(january.details.health, "409.16")
    assert_amount(february.details.health, "432.54")
  end

  test "a lump sum partner pays the health contribution of the revenue since January" do
    entries = [
      revenue(~D[2026-01-10], "50000"),
      revenue(~D[2026-03-10], "100000"),
      revenue(~D[2026-06-10], "200000"),
      cost(~D[2026-01-11], "40000")
    ]

    forecasts = forecasts(entries, %{income_tax: :lump_sum})

    assert_amount(Enum.at(forecasts, 0).details.health, "498.35")
    assert_amount(Enum.at(forecasts, 1).details.health, "498.35")
    assert_amount(Enum.at(forecasts, 2).details.health, "830.58")
    assert_amount(Enum.at(forecasts, 4).details.health, "830.58")
    assert_amount(Enum.at(forecasts, 5).details.health, "1495.04")
    assert_amount(Enum.at(forecasts, 5).details.health_base, 350_000)
  end

  describe "Mały ZUS Plus" do
    defp small_plus_base(entries, overrides \\ %{}) do
      [january | _] = forecasts(entries, Map.put(overrides, :social_insurance, :small_plus))
      january.details.social_base
    end

    test "is half of the previous year's average monthly income" do
      # 73 000 of income over 365 days is 6 000 a month, half of it 3 000.
      entries = [revenue(~D[2025-03-10], "80000"), cost(~D[2025-04-10], "7000")]
      assert_amount(small_plus_base(entries), "3000.00")

      # On the lump sum half of the revenue is the income.
      assert_amount(
        small_plus_base([revenue(~D[2025-03-10], "146000")], %{income_tax: :lump_sum}),
        "3000.00"
      )
    end

    test "stays between the preferential and the full base" do
      assert_amount(small_plus_base([cost(~D[2025-03-10], "5000")]), "1441.80")
      assert_amount(small_plus_base([revenue(~D[2025-03-10], "365000")]), "5652.00")
    end
  end
end
