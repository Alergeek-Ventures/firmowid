defmodule Firmowid.Taxes.Forecast.PaymentHistoryTest do
  use ExUnit.Case, async: true

  alias Firmowid.Taxes.Forecast.PaymentHistory

  @history_start ~D[2020-01-01]
  @opts [
    year: 2026,
    legal_form: :sole_proprietorship,
    owner_pays?: true,
    history_start: @history_start
  ]

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
             PaymentHistory.adjust(forecasts, reference, payments, ~D[2026-11-10], @opts)

    # A period past due stays as it is, and so does one beyond the horizon (31 January 2027).
    assert past == hd(forecasts)
    assert beyond == List.last(forecasts)
    assert amounts([running, next]) == [1000, 1000]

    assert %{documents_amount: documents_amount, typical_payment: typical} = running.details
    assert Decimal.equal?(documents_amount, 0)
    assert Decimal.equal?(typical, 1000)
    assert next.details == running.details
  end

  test "keeps a forecast within 1.5 times of the typical payment" do
    forecasts = [
      forecast("2026-11", ~D[2026-12-25], 700),
      forecast("2026-12", ~D[2027-01-25], 1400)
    ]

    months = ["2026-07", "2026-08", "2026-09"]
    payments = for month <- months, do: payment(month, 1000)

    assert PaymentHistory.adjust(forecasts, reference(months, 0), payments, ~D[2026-11-10], @opts) ==
             forecasts
  end

  test "keeps a low forecast when the documents explained the reference payments" do
    forecasts = [forecast("2026-11", ~D[2026-12-25], 0)]
    months = ["2026-07", "2026-08", "2026-09"]
    payments = for month <- months, do: payment(month, 1000)

    # The tax-scale January case: the documents explain the payments, so a zero is legitimate.
    assert PaymentHistory.adjust(
             forecasts,
             reference(months, 1000),
             payments,
             ~D[2026-11-10],
             @opts
           ) ==
             forecasts
  end

  test "keeps a forecast when only one of the three periods was paid" do
    forecasts = [forecast("2026-11", ~D[2026-12-25], 0)]
    months = ["2026-07", "2026-08", "2026-09"]
    payments = [payment("2026-09", 1000)]

    assert PaymentHistory.adjust(forecasts, reference(months, 0), payments, ~D[2026-11-10], @opts) ==
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

    assert [adjusted] =
             PaymentHistory.adjust(forecasts, reference, payments, today,
               year: 2027,
               legal_form: nil,
               owner_pays?: false,
               history_start: @history_start
             )

    assert Decimal.equal?(adjusted.amount, 1000)
    assert Decimal.equal?(adjusted.details.documents_amount, 100)
    assert Decimal.equal?(adjusted.details.typical_payment, 1000)

    # Without the reference forecasts of last year the group is left alone.
    assert PaymentHistory.adjust(forecasts, forecasts, payments, today,
             year: 2027,
             legal_form: nil,
             owner_pays?: false,
             history_start: @history_start
           ) == forecasts
  end

  test "lowers a forecast far above the payments" do
    forecasts = [forecast("2026-11", ~D[2026-12-25], 5000, :zus)]
    months = ["2026-07", "2026-08", "2026-09"]
    payments = for month <- months, do: payment(month, 1000, :zus)

    assert [adjusted] =
             PaymentHistory.adjust(
               forecasts,
               reference(months, 5000, :zus),
               payments,
               ~D[2026-11-10],
               @opts
             )

    assert Decimal.equal?(adjusted.amount, 1000)
    assert Decimal.equal?(adjusted.details.documents_amount, 5000)
  end

  test "leaves a group alone when the documents are within 1.5 times of the payments" do
    forecasts = [forecast("2026-11", ~D[2026-12-25], 5000)]
    months = ["2026-07", "2026-08", "2026-09"]
    payments = for month <- months, do: payment(month, 1000)

    # 1400 + 1400 + 1400 is below 1.5 times of 3000, so a far higher forecast still stands.
    assert PaymentHistory.adjust(
             forecasts,
             reference(months, 1400),
             payments,
             ~D[2026-11-10],
             @opts
           ) ==
             forecasts
  end

  test "leaves an owner's payments out unless the owner pays" do
    forecast = %{forecast("2026-11", ~D[2026-12-25], 0, :zus) | member_id: "owner"}
    months = ["2026-07", "2026-08", "2026-09"]
    payments = for month <- months, do: payment(month, 1000, :zus)

    reference =
      for month <- months, do: %{forecast(month, ~D[2026-01-01], 0, :zus) | member_id: "owner"}

    today = ~D[2026-11-10]

    assert PaymentHistory.adjust([forecast], reference, payments, today,
             owner_pays?: false,
             year: 2026,
             history_start: @history_start
           ) == [forecast]

    assert [%{amount: amount}] =
             PaymentHistory.adjust([forecast], reference, payments, today, @opts)

    assert Decimal.equal?(amount, 1000)
  end

  describe "a short bank history" do
    # VAT of a month is due on the 25th of the next one, a quarter's on the 25th after it.
    test "forecasts from the one quarterly payment the history covers" do
      payments = [payment("2026-Q2", 1200, :cit)]
      opts = Keyword.put(@opts, :history_start, ~D[2026-07-01])

      # Q1 is due on 20 April 2026, before the history, and not known; Q2 (20 July) is the only one.
      assert [%{period: "2026-Q3"} = quarter | _] =
               PaymentHistory.adjust([], [], payments, ~D[2026-08-10], opts)

      assert Decimal.equal?(quarter.amount, 1200)
    end

    test "takes the mean of two known periods and counts a zero inside the history" do
      payments = [payment("2026-08", 1000), payment("2026-09", 2000)]
      opts = Keyword.put(@opts, :history_start, ~D[2026-09-01])

      # July (due 25 August) is not known: the mean of August and September.
      assert [november | _] = PaymentHistory.adjust([], [], payments, ~D[2026-11-10], opts)
      assert Decimal.equal?(november.amount, 1500)

      # A paid period and an unpaid one inside the history: 2000 and 0 give 1000.
      assert [november | _] =
               PaymentHistory.adjust([], [], [payment("2026-09", 2000)], ~D[2026-11-10], opts)

      assert Decimal.equal?(november.amount, 1000)
    end

    test "compares only the known periods when adjusting forecasts from documents" do
      forecasts = [forecast("2026-11", ~D[2026-12-25], 0)]
      opts = Keyword.put(@opts, :history_start, ~D[2026-09-01])
      payments = [payment("2026-08", 1000), payment("2026-09", 1000)]

      # Only August and September count: no reference forecast of July is needed.
      assert [adjusted] =
               PaymentHistory.adjust(
                 forecasts,
                 reference(["2026-08", "2026-09"], 0),
                 payments,
                 ~D[2026-11-10],
                 opts
               )

      assert Decimal.equal?(adjusted.amount, 1000)
    end
  end

  describe "a kind the settings do not forecast" do
    defp vat_payments do
      [
        payment("2026-06", 5000),
        payment("2026-07", 900),
        payment("2026-08", 1100),
        payment("2026-09", 1000),
        payment("2026-10", 1200)
      ]
    end

    test "is forecast from the payments for the unpaid periods that are not past due" do
      # The periods due before 10 November are the ones to September: the median of July to September.
      assert [november, december] =
               PaymentHistory.adjust([], [], vat_payments(), ~D[2026-11-10], @opts)

      assert %{kind: :vat, period: "2026-11", member_id: nil, due_date: ~D[2026-12-28]} = november
      assert november.period_start == ~D[2026-11-01]
      assert november.period_end == ~D[2026-11-30]
      assert november.description =~ "11/2026"
      assert Decimal.equal?(november.amount, 1000)
      assert Decimal.equal?(november.details.typical_payment, 1000)
      assert Map.keys(november.details) == [:typical_payment]

      # October is paid already, and nothing is forecast beyond the horizon of 31 January 2027.
      assert %{period: "2026-12", due_date: ~D[2027-01-25]} = december
    end

    test "takes the frequency of the latest paid period and the day of the payer" do
      payments = [
        payment("2026-Q1", 1000, :cit),
        payment("2026-Q2", 3000, :cit),
        payment("2026-Q3", 2000, :cit)
      ]

      assert [%{period: "2026-Q4", due_date: ~D[2027-01-20]} = quarter] =
               PaymentHistory.adjust([], [], payments, ~D[2026-11-10], @opts)

      assert Decimal.equal?(quarter.amount, 2000)

      # A limited company pays ZUS by the 15th of the next month, an owner by the 20th.
      zus = for month <- ["2026-07", "2026-08", "2026-09"], do: payment(month, 100, :zus)

      limited = [
        year: 2026,
        legal_form: :limited_company,
        owner_pays?: false,
        history_start: @history_start
      ]

      due = fn opts ->
        []
        |> PaymentHistory.adjust([], zus, ~D[2026-11-10], opts)
        |> Enum.find(&(&1.period == "2026-11"))
        |> Map.fetch!(:due_date)
      end

      assert due.(limited) == ~D[2026-12-15]
      assert due.(@opts) == ~D[2026-12-21]
    end

    test "is not forecast for a kind the settings forecast, or when the typical payment is zero" do
      forecasts = [forecast("2026-11", ~D[2026-12-25], 1000)]
      months = ["2026-07", "2026-08", "2026-09"]

      assert PaymentHistory.adjust(
               forecasts,
               reference(months, 1000),
               vat_payments(),
               ~D[2026-11-10],
               @opts
             ) ==
               forecasts

      assert PaymentHistory.adjust(
               [],
               [],
               for(month <- months, do: payment(month, 0)),
               ~D[2026-11-10],
               @opts
             ) == []
    end
  end
end
