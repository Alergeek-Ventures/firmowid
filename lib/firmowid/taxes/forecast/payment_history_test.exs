defmodule Firmowid.Taxes.Forecast.PaymentHistoryTest do
  use ExUnit.Case, async: true

  alias Firmowid.Taxes.Forecast.PaymentHistory

  defp forecast(period, due_date, amount, kind \\ :vat) do
    %{
      kind: kind,
      period: period,
      period_start: period_start(period),
      amount: Decimal.new(amount),
      due_date: due_date,
      member_id: nil,
      details: %{}
    }
  end

  defp period_start(<<year::binary-size(4), "-Q", quarter::binary>>),
    do: Date.new!(String.to_integer(year), String.to_integer(quarter) * 3 - 2, 1)

  defp period_start(<<year::binary-size(4), "-", month::binary>>),
    do: Date.new!(String.to_integer(year), String.to_integer(month), 1)

  defp payment(period, amount, kind \\ :vat), do: %{kind: kind, period: period, amount: Decimal.new(amount)}

  defp amounts(forecasts), do: Enum.map(forecasts, &Decimal.to_integer(&1.amount))

  defp reference(periods, amount, kind \\ :vat),
    do: for(period <- periods, do: forecast(period, ~D[2026-01-01], amount, kind))

  test "replaces what the documents give with the median of the last three payments" do
    forecasts = [
      forecast("2026-09", ~D[2026-10-26], 0),
      forecast("2026-10", ~D[2026-11-25], 0),
      forecast("2026-11", ~D[2026-12-25], 0),
      forecast("2027-02", ~D[2027-03-25], 0)
    ]

    # July to September are the periods due before the 10th of November; June is older.
    payments = [
      payment("2026-06", 5000),
      payment("2026-07", 900),
      payment("2026-08", 1100),
      payment("2026-09", 1000)
    ]

    reference = reference(["2026-07", "2026-08", "2026-09"], 0)

    assert [past, running, next, beyond] =
             PaymentHistory.adjust(forecasts, reference, payments, ~D[2026-11-10])

    # A period past due stays as it is, and so does one beyond the horizon (31 January 2027).
    assert past == hd(forecasts)
    assert beyond == List.last(forecasts)
    assert amounts([running, next]) == [1000, 1000]

    assert %{documents_amount: documents_amount, typical_payment: typical} = running.details
    assert Decimal.equal?(documents_amount, 0)
    assert Decimal.equal?(typical, 1000)
    assert next.details == running.details
  end

  test "keeps a forecast that is at least half of the typical payment" do
    forecasts = [
      forecast("2026-11", ~D[2026-12-25], 500),
      forecast("2026-12", ~D[2027-01-25], 600)
    ]

    months = ["2026-07", "2026-08", "2026-09"]
    payments = for month <- months, do: payment(month, 1000)

    assert PaymentHistory.adjust(forecasts, reference(months, 0), payments, ~D[2026-11-10]) ==
             forecasts
  end

  test "keeps a low forecast when the documents explained the reference payments" do
    forecasts = [forecast("2026-11", ~D[2026-12-25], 0)]
    months = ["2026-07", "2026-08", "2026-09"]
    payments = for month <- months, do: payment(month, 1000)

    # The tax-scale January case: the documents explain the payments, so a zero is legitimate.
    assert PaymentHistory.adjust(forecasts, reference(months, 1000), payments, ~D[2026-11-10]) ==
             forecasts
  end

  test "keeps a forecast when only one of the three periods was paid" do
    forecasts = [forecast("2026-11", ~D[2026-12-25], 0)]
    months = ["2026-07", "2026-08", "2026-09"]
    payments = [payment("2026-09", 1000)]

    assert PaymentHistory.adjust(forecasts, reference(months, 0), payments, ~D[2026-11-10]) ==
             forecasts
  end

  test "finds the reference quarters in the year before" do
    forecasts = [forecast("2027-Q1", ~D[2027-04-20], 100, :cit)]
    today = ~D[2027-02-10]

    # The quarters due before 10 February 2027 are the second to the fourth of 2026.
    payments = [
      payment("2026-Q1", 5000, :cit),
      payment("2026-Q2", 900, :cit),
      payment("2026-Q3", 1100, :cit),
      payment("2026-Q4", 1000, :cit)
    ]

    reference = reference(["2026-Q2", "2026-Q3", "2026-Q4"], 0, :cit)

    assert PaymentHistory.reference_years(forecasts, today) == [2026]

    assert [adjusted] = PaymentHistory.adjust(forecasts, reference, payments, today)
    assert Decimal.equal?(adjusted.amount, 1000)
    assert Decimal.equal?(adjusted.details.documents_amount, 100)
    assert Decimal.equal?(adjusted.details.typical_payment, 1000)

    # Without the reference forecasts of last year the group is left alone.
    assert PaymentHistory.adjust(forecasts, forecasts, payments, today) == forecasts
  end
end
