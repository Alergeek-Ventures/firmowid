defmodule Firmowid.Taxes.Forecast.CitTest do
  use ExUnit.Case, async: true

  alias Firmowid.Taxes.Forecast.Cit

  defp revenue(date, amount), do: %{side: :revenue, amount: Decimal.new(amount), date: date}
  defp cost(date, amount), do: %{side: :cost, amount: Decimal.new(amount), date: date}

  defp amounts(forecasts), do: Enum.map(forecasts, &Decimal.to_integer(&1.amount))

  test "monthly advances are cumulative and a loss month lowers the later ones" do
    entries = [
      revenue(~D[2026-01-10], "10000"),
      revenue(~D[2026-03-10], "1000"),
      cost(~D[2026-02-10], "8000"),
      cost(~D[2026-03-15], "6000")
    ]

    forecasts = Cit.forecast(entries, %{cit_rate: :standard, cit_advances: :monthly}, 2026)

    assert length(forecasts) == 12

    # January 19% of 10 000; February's income of 2 000 owes 380, so 0 more; March's of -3 000 owes
    # nothing and keeps the 1 900 paid; April on, the 1 900 is not owed again.
    assert [1900, 0, 0, 0 | _] = amounts(forecasts)
    assert Decimal.equal?(Enum.at(forecasts, 1).details.income, 2000)
    assert Decimal.equal?(Enum.at(forecasts, 1).details.tax, 380)
    assert Decimal.equal?(Enum.at(forecasts, 1).details.advances_before, 1900)
    assert Enum.at(forecasts, 2).details.rate == 19
  end

  test "a loss month lowers what a later month owes" do
    entries = [
      revenue(~D[2026-01-10], "10000"),
      cost(~D[2026-02-10], "20000"),
      revenue(~D[2026-03-10], "30000")
    ]

    forecasts = Cit.forecast(entries, %{cit_rate: :reduced, cit_advances: :monthly}, 2026)

    # January 900; February's cumulative income is negative; March's 20 000 owes 1 800, less the 900.
    assert [900, 0, 900 | _] = amounts(forecasts)
  end

  test "quarterly advances are due on the 20th after the quarter, the last on 20 January" do
    entries = [revenue(~D[2026-02-10], "10000"), revenue(~D[2026-11-10], "10000")]

    forecasts = Cit.forecast(entries, %{cit_rate: :reduced, cit_advances: :quarterly}, 2026)

    assert [900, 0, 0, 900] = amounts(forecasts)

    assert [~D[2026-04-20], ~D[2026-07-20], ~D[2026-10-20], ~D[2027-01-20]] ==
             Enum.map(forecasts, & &1.due_date)

    assert %{kind: :cit, period: "2026-Q1", member_id: nil, details: %{revenue: revenue}} =
             hd(forecasts)

    assert Decimal.equal?(revenue, 10_000)
  end

  test "rounds the income and the tax to full złoty" do
    entries = [revenue(~D[2026-01-10], "1000.50"), cost(~D[2026-01-11], "0.10")]

    [january | _] = Cit.forecast(entries, %{cit_rate: :standard, cit_advances: :monthly}, 2026)

    # 1000.40 rounds to 1000; 19% is 190.
    assert Decimal.equal?(january.details.tax, 190)

    [first | _] =
      Cit.forecast(
        [revenue(~D[2026-01-10], "100.50")],
        %{cit_rate: :reduced, cit_advances: :monthly},
        2026
      )

    # 101 at 9% is 9.09, so 9.
    assert Decimal.equal?(first.amount, 9)
  end

  test "ignores entries of other years and gives nothing for the simplified form" do
    entries = [revenue(~D[2025-12-31], "10000"), revenue(~D[2027-01-01], "10000")]

    assert entries
           |> Cit.forecast(%{cit_rate: :reduced, cit_advances: :quarterly}, 2026)
           |> amounts() == [0, 0, 0, 0]

    assert Cit.forecast(entries, %{cit_rate: :reduced, cit_advances: :simplified}, 2026) == []
  end
end
