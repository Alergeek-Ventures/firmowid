defmodule Firmowid.Taxes.Forecast.ProjectionTest do
  use ExUnit.Case, async: true

  alias Firmowid.Taxes.Forecast.Projection

  defp entry(side, amount, date), do: %{side: side, amount: Decimal.new(amount), date: date}

  # Projected entries as {side, amount, date}, in a stable order.
  defp projected(entries, today, until) do
    entries
    |> Projection.project(today, until)
    |> Enum.map(fn entry ->
      assert entry.projected?
      {entry.side, Decimal.to_string(entry.amount, :normal), entry.date}
    end)
    |> Enum.sort_by(fn {side, _amount, date} -> {side, Date.to_erl(date)} end)
  end

  test "the rest of the month is what the three months before booked after the same day" do
    # Invoices at the end of the month: nothing is booked by the 10th, all of it comes after.
    end_of_month = [
      entry(:output, "100", ~D[2026-08-28]),
      entry(:output, "200", ~D[2026-09-29]),
      entry(:output, "300", ~D[2026-10-30]),
      # The current month and the one before the history do not count.
      entry(:output, "9000", ~D[2026-07-30]),
      entry(:output, "9000", ~D[2026-11-05])
    ]

    assert [{:output, "200.00", ~D[2026-11-30]}] =
             projected(end_of_month, ~D[2026-11-10], ~D[2026-11-30])

    # Spread evenly: of each month's three days only the 12th and the 20th are after the 10th.
    spread =
      for month <- [8, 9, 10],
          day <- [3, 12, 20],
          do: entry(:input, "5", Date.new!(2026, month, day))

    assert [{:input, "10.00", ~D[2026-11-30]}] = projected(spread, ~D[2026-11-10], ~D[2026-11-30])
  end

  test "projects each side separately and never a refund" do
    entries = [
      entry(:output, "300", ~D[2026-10-20]),
      entry(:input, "60", ~D[2026-10-25]),
      entry(:refund, "500", ~D[2026-10-26])
    ]

    # October is the only month of history, as a refund is not a business entry.
    assert [{:input, "60.00", ~D[2026-11-30]}, {:output, "300.00", ~D[2026-11-30]}] =
             projected(entries, ~D[2026-11-10], ~D[2026-11-30])
  end

  test "projects the whole months after the current one up to the end of the quarter" do
    entries = [
      entry(:revenue, "300", ~D[2026-07-05]),
      entry(:revenue, "600", ~D[2026-08-15]),
      entry(:revenue, "900", ~D[2026-09-25])
    ]

    # The rest of October is what came after the 10th: nothing in July, 600 in August and 900 in
    # September, so the median is 600. November and December get the median month of 300, 600, 900.
    assert [
             {:revenue, "600.00", ~D[2026-10-31]},
             {:revenue, "600.00", ~D[2026-11-30]},
             {:revenue, "600.00", ~D[2026-12-31]}
           ] = projected(entries, ~D[2026-10-10], ~D[2026-12-31])

    # Only the whole months up to `until` are projected.
    assert [{:revenue, "600.00", ~D[2026-10-31]}, {:revenue, "600.00", ~D[2026-11-30]}] =
             projected(entries, ~D[2026-10-10], ~D[2026-11-30])
  end

  test "one unusual month does not move the projection of steady months" do
    # Invoices on the last day of every month, the middle month higher.
    entries = [
      entry(:output, "1000", ~D[2026-08-31]),
      entry(:output, "1200", ~D[2026-09-30]),
      entry(:output, "1000", ~D[2026-10-31])
    ]

    assert [{:output, "1000.00", ~D[2026-11-30]}, {:output, "1000.00", ~D[2026-12-31]}] =
             projected(entries, ~D[2026-11-10], ~D[2026-12-31])
  end

  test "uses the months that exist when there are fewer than three" do
    entries = [entry(:output, "100", ~D[2026-10-20]), entry(:output, "300", ~D[2026-10-25])]

    # Only October exists before November: its whole 400 after the 10th is the rest, not 400 / 3.
    assert [{:output, "400.00", ~D[2026-11-30]}] =
             projected(entries, ~D[2026-11-10], ~D[2026-11-30])

    two_months = [entry(:output, "100", ~D[2026-09-20]), entry(:output, "300", ~D[2026-10-25])]

    assert [{:output, "200.00", ~D[2026-11-30]}, {:output, "200.00", ~D[2026-12-31]}] =
             projected(two_months, ~D[2026-11-10], ~D[2026-12-31])
  end

  test "projects nothing without history" do
    assert [] = Projection.project([], ~D[2026-11-10], ~D[2026-11-30])

    # Entries of the current month and later are not history.
    assert [] =
             Projection.project(
               [entry(:output, "100", ~D[2026-11-03]), entry(:output, "100", ~D[2026-12-03])],
               ~D[2026-11-10],
               ~D[2026-12-31]
             )

    assert [] =
             Projection.project(
               [entry(:refund, "100", ~D[2026-10-03])],
               ~D[2026-11-10],
               ~D[2026-11-30]
             )
  end

  test "projects nothing for the current month on its last day" do
    # March has a 31st that April does not, but on 30 April nothing of April is left.
    entries = [entry(:output, "300", ~D[2026-03-31]), entry(:output, "300", ~D[2026-02-20])]

    assert [] = projected(entries, ~D[2026-04-30], ~D[2026-04-30])

    # The next whole month is still projected: February and March, 600 over 2 months.
    assert [{:output, "300.00", ~D[2026-05-31]}] =
             projected(entries, ~D[2026-04-30], ~D[2026-05-31])
  end

  test "a month shorter than today's day brings nothing to the rest of the month" do
    # On 30 March, February (28 days) has no 29th or 30th, and 31 March is the only day left.
    entries = [
      entry(:output, "300", ~D[2026-02-28]),
      entry(:output, "30", ~D[2026-01-31]),
      entry(:output, "60", ~D[2025-12-31])
    ]

    assert [{:output, "30.00", ~D[2026-03-31]}] =
             projected(entries, ~D[2026-03-30], ~D[2026-03-31])
  end

  test "negative amounts take part in the sums" do
    entries = [entry(:output, "300", ~D[2026-09-20]), entry(:output, "-90", ~D[2026-10-20])]

    assert [{:output, "105.00", ~D[2026-11-30]}] =
             projected(entries, ~D[2026-11-10], ~D[2026-11-30])
  end

  test "a document already booked for a later day lowers the projection, not below nothing" do
    history = for month <- [8, 9, 10], do: entry(:output, "300", Date.new!(2026, month, 28))

    # 100 of the typical 300 is already booked for the 20th.
    assert [{:output, "200.00", ~D[2026-11-30]}] =
             projected(
               [entry(:output, "100", ~D[2026-11-20]) | history],
               ~D[2026-11-10],
               ~D[2026-11-30]
             )

    # More than usual is booked: nothing is added, and nothing is taken away.
    assert [] =
             projected(
               [entry(:output, "500", ~D[2026-11-20]) | history],
               ~D[2026-11-10],
               ~D[2026-11-30]
             )
  end

  test "a correction already booked for a later day lowers a negative projection the same way" do
    history = for month <- [8, 9, 10], do: entry(:output, "-100", Date.new!(2026, month, 20))

    assert [{:output, "-60.00", ~D[2026-11-30]}] =
             projected(
               [entry(:output, "-40", ~D[2026-11-20]) | history],
               ~D[2026-11-10],
               ~D[2026-11-30]
             )
  end

  test "projected? tells a projected entry from a document" do
    assert Projection.projected?(%{projected?: true})
    refute Projection.projected?(entry(:output, "1", ~D[2026-01-01]))
  end
end
