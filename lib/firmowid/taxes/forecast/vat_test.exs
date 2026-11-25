defmodule Firmowid.Taxes.Forecast.VatTest do
  use ExUnit.Case, async: true

  alias Firmowid.Taxes.Forecast.Vat

  defp entry(side, amount, date), do: %{side: side, amount: Decimal.new(amount), date: date}

  defp assert_decimal(actual, expected) do
    assert Decimal.equal?(actual, Decimal.new(expected)),
           "expected #{expected}, got #{Decimal.to_string(actual)}"
  end

  describe "forecast/3 refunds" do
    test "a refund lowers the surplus carried into its period, never below zero" do
      forecasts =
        Vat.forecast(
          [
            entry(:input, "1000", ~D[2026-01-10]),
            entry(:refund, "400", ~D[2026-02-15]),
            entry(:refund, "900", ~D[2026-03-15]),
            entry(:output, "100", ~D[2026-04-10])
          ],
          :monthly,
          2026
        )

      [january, february, march, april | _] = forecasts

      assert_decimal(january.details.refunded, "0")

      # The refund of 400 leaves 600 of January's 1 000 for February to use.
      assert_decimal(february.details.refunded, "400")
      assert_decimal(february.details.carried_over, "600")

      # A refund above the surplus leaves nothing, not a negative carry.
      assert_decimal(march.details.refunded, "900")
      assert_decimal(march.details.carried_over, "0")
      assert_decimal(april.details.carried_over, "0")
      assert_decimal(april.amount, "100")
    end
  end

  describe "forecast/3 monthly" do
    test "pays output less input VAT, each rounded half-up to a full złoty" do
      forecasts =
        Vat.forecast(
          [
            entry(:output, "100.30", ~D[2026-03-02]),
            entry(:output, "50.20", ~D[2026-03-20]),
            entry(:input, "20.50", ~D[2026-03-10]),
            # Another year does not count.
            entry(:output, "999", ~D[2025-03-10]),
            entry(:input, "999", ~D[2027-03-10])
          ],
          :monthly,
          2026
        )

      assert Enum.map(forecasts, & &1.period) ==
               for(month <- 1..12, do: "2026-#{String.pad_leading("#{month}", 2, "0")}")

      march = Enum.find(forecasts, &(&1.period == "2026-03"))
      # 150.50 rounds to 151, 20.50 to 21.
      assert_decimal(march.details.output_vat, "151")
      assert_decimal(march.details.input_vat, "21")
      assert_decimal(march.amount, "130")

      for forecast <- forecasts, forecast.period != "2026-03" do
        assert_decimal(forecast.amount, "0")
      end
    end

    test "a month with more input than output pays nothing and lowers the following months" do
      forecasts =
        Vat.forecast(
          [
            entry(:input, "300", ~D[2026-01-10]),
            entry(:output, "100", ~D[2026-02-10]),
            entry(:output, "150", ~D[2026-03-10]),
            entry(:output, "400", ~D[2026-04-10])
          ],
          :monthly,
          2026
        )

      amounts = forecasts |> Enum.take(4) |> Enum.map(& &1.amount)

      # 300 surplus: 200 left after February, 50 after March, April pays 350.
      for {amount, expected} <- Enum.zip(amounts, ["0", "0", "0", "350"]),
          do: assert_decimal(amount, expected)
    end

    test "falls due on the 25th of the next month, moved off days off" do
      due = fn forecasts, period -> Enum.find(forecasts, &(&1.period == period)).due_date end
      forecasts = Vat.forecast([], :monthly, 2026)

      # 25 December is a holiday, then 26 December too, then a weekend.
      assert due.(forecasts, "2026-11") == ~D[2026-12-28]
      # 25 April 2026 is a Saturday.
      assert due.(forecasts, "2026-03") == ~D[2026-04-27]
      assert due.(forecasts, "2026-04") == ~D[2026-05-25]
    end
  end

  describe "forecast/3 quarterly" do
    test "sums the quarter's months" do
      forecasts =
        Vat.forecast(
          [
            entry(:output, "100", ~D[2026-01-15]),
            entry(:output, "200", ~D[2026-03-31]),
            entry(:input, "50", ~D[2026-02-01]),
            entry(:output, "70", ~D[2026-04-01])
          ],
          :quarterly,
          2026
        )

      assert Enum.map(forecasts, & &1.period) == ["2026-Q1", "2026-Q2", "2026-Q3", "2026-Q4"]
      assert_decimal(Enum.at(forecasts, 0).amount, "250")
      assert_decimal(Enum.at(forecasts, 1).amount, "70")
      assert Enum.at(forecasts, 0).due_date == ~D[2026-04-27]
    end
  end

  describe "on_payment/3" do
    test "brings proportional VAT on the payment dates, in date order" do
      parts =
        Vat.on_payment(Decimal.new("23"), Decimal.new("123"), [
          {~D[2026-05-10], Decimal.new("23")},
          {~D[2026-04-10], Decimal.new("100")}
        ])

      assert [{~D[2026-04-10], first}, {~D[2026-05-10], second}] = parts
      assert_decimal(Decimal.round(first, 4), "18.6992")
      assert_decimal(Decimal.round(second, 4), "4.3008")
    end

    test "caps payments beyond the gross so the parts never exceed the VAT" do
      parts =
        Vat.on_payment(Decimal.new("23"), Decimal.new("123"), [
          {~D[2026-04-10], Decimal.new("123")},
          {~D[2026-05-10], Decimal.new("50")}
        ])

      assert [{~D[2026-04-10], first}, {~D[2026-05-10], second}] = parts
      assert_decimal(first, "23")
      assert_decimal(second, "0")
    end

    test "gives nothing without payments" do
      assert Vat.on_payment(Decimal.new("23"), Decimal.new("123"), []) == []
    end
  end
end
