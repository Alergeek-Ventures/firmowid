defmodule Firmowid.Taxes.Forecast.ExpectationsTest do
  use ExUnit.Case, async: true

  alias Firmowid.Finances.ExpectedTransaction
  alias Firmowid.Taxes.Forecast.Expectations

  @today ~D[2026-11-25]
  @member_id "0192d6f0-0000-7000-8000-000000000001"

  defp forecast(attrs) do
    Map.merge(
      %{
        kind: :vat,
        period: "2026-11",
        period_start: ~D[2026-11-01],
        period_end: ~D[2026-11-30],
        amount: Decimal.new("100"),
        due_date: ~D[2026-12-25],
        description: "VAT za 11/2026",
        member_id: nil,
        details: %{}
      },
      Map.new(attrs)
    )
  end

  defp record(attrs \\ []) do
    struct!(
      ExpectedTransaction,
      Map.merge(
        %{
          forecast_key: "vat:2026-11",
          date: ~D[2026-12-25],
          amount: Money.new!(:PLN, "-100"),
          description: "VAT za 11/2026",
          counterparty_name: "Urząd Skarbowy",
          is_fulfilled: false
        },
        Map.new(attrs)
      )
    )
  end

  test "creates an expectation for a payment that is due, as an expense to its institution" do
    forecasts = [
      forecast(amount: Decimal.new("100.50")),
      forecast(kind: :zus, period: "2026-11", member_id: @member_id, due_date: ~D[2026-12-21]),
      forecast(
        kind: :cit,
        period: "2026-Q4",
        period_start: ~D[2026-10-01],
        due_date: ~D[2027-01-20]
      )
    ]

    assert [{:create, vat}, {:create, zus}, {:create, cit}] =
             Expectations.plan(forecasts, [], @today)

    assert %{
             forecast_key: "vat:2026-11",
             date: ~D[2026-12-25],
             counterparty_name: "Urząd Skarbowy"
           } = vat

    assert Money.equal?(vat.amount, Money.new!(:PLN, "-100.50"))
    assert vat.description == "VAT za 11/2026"

    assert %{forecast_key: "zus:2026-11:" <> @member_id, counterparty_name: "ZUS"} = zus
    assert %{forecast_key: "cit:2026-Q4", counterparty_name: "Urząd Skarbowy"} = cit
  end

  test "creates an expectation for a period that starts within the horizon, not after it" do
    # The horizon of 25 November 2026 is 31 January 2027.
    within = forecast(period: "2027-01", period_start: ~D[2027-01-01], due_date: ~D[2027-02-25])
    after_it = forecast(period: "2027-02", period_start: ~D[2027-02-01], due_date: ~D[2027-03-25])

    assert [{:create, %{forecast_key: "vat:2027-01"}}] =
             Expectations.plan([within, after_it], [], @today)
  end

  test "ignores a period beyond the horizon, a payment past due and one without an amount" do
    forecasts = [
      forecast(period: "2027-02", period_start: ~D[2027-02-01], due_date: ~D[2027-03-25]),
      forecast(period: "2026-10", period_start: ~D[2026-10-01], due_date: ~D[2026-11-24]),
      forecast(period: "2026-09", period_start: ~D[2026-09-01], amount: Decimal.new(0))
    ]

    assert Expectations.plan(forecasts, [], @today) == []
  end

  test "a payment due today is still expected" do
    assert [{:create, %{forecast_key: "vat:2026-10"}}] =
             Expectations.plan(
               [forecast(period: "2026-10", period_start: ~D[2026-10-01], due_date: @today)],
               [],
               @today
             )
  end

  test "updates an unfulfilled expectation only when the forecast changed" do
    existing = record()

    assert Expectations.plan([forecast([])], [existing], @today) == []

    assert [{:update, ^existing, changes}] =
             Expectations.plan(
               [
                 forecast(
                   amount: Decimal.new("120"),
                   description: "VAT za 11/2026 (korekta)",
                   due_date: ~D[2026-12-28]
                 )
               ],
               [existing],
               @today
             )

    assert changes.date == ~D[2026-12-28]
    assert Money.equal?(changes.amount, Money.new!(:PLN, "-120"))
    assert changes.description == "VAT za 11/2026 (korekta)"
    assert changes |> Map.keys() |> Enum.sort() == [:amount, :date, :description]
  end

  test "keeps and updates an unfulfilled expectation past its due date, never recreates it" do
    past = [period: "2026-10", period_start: ~D[2026-10-01], due_date: ~D[2026-11-24]]
    existing = record(forecast_key: "vat:2026-10", date: ~D[2026-11-24])

    assert [{:update, ^existing, %{amount: amount}}] =
             Expectations.plan(
               [forecast(past ++ [amount: Decimal.new("130")])],
               [existing],
               @today
             )

    assert Money.equal?(amount, Money.new!(:PLN, "-130"))
    assert Expectations.plan([forecast(past)], [existing], @today) == []
  end

  test "leaves a fulfilled expectation untouched, whatever the forecast says" do
    fulfilled = record(is_fulfilled: true)

    assert Expectations.plan([forecast(amount: Decimal.new("999"))], [fulfilled], @today) == []
    assert Expectations.plan([forecast(amount: Decimal.new(0))], [fulfilled], @today) == []
    assert Expectations.plan([], [fulfilled], @today) == []
  end

  test "removes an unfulfilled expectation whose forecast has no amount or is gone" do
    no_amount = record(forecast_key: "vat:2026-11")
    gone = record(forecast_key: "cit:2026-Q3")
    last_year = record(forecast_key: "zus:2025-12:" <> @member_id, date: ~D[2026-01-20])

    assert [{:destroy, ^no_amount}, {:destroy, ^gone}, {:destroy, ^last_year}] =
             Expectations.plan(
               [forecast(amount: Decimal.new(0))],
               [no_amount, gone, last_year],
               @today
             )
  end

  test "does not remove an expectation of an older year" do
    assert Expectations.plan([], [record(forecast_key: "vat:2024-12")], @today) == []
  end

  test "ignores expectations without a forecast key" do
    manual = record(forecast_key: nil, description: "Rent")

    assert [{:create, %{forecast_key: "vat:2026-11"}}] =
             Expectations.plan([forecast([])], [manual], @today)

    assert Expectations.plan([], [manual], @today) == []
  end
end
