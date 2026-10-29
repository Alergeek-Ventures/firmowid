defmodule Firmowid.Payroll.UserSalary.Calculations.PayoutEstimatesTest do
  @moduledoc "Checks hypothetical payouts and their selection without database access."
  use ExUnit.Case, async: true

  alias Firmowid.Payroll.UserSalary.Calculations.PayoutEstimates

  test "estimates common payouts without assuming youth relief for an unknown birthday" do
    for {type, expected} <- [
          uop: [uop: "7147.39"],
          uz: [uz_health: "8140.00", uz_social: "7223.34"],
          uod: [uod_20: "9040.00", uod_50: "9400.00"],
          b2b: [b2b: "10000.00"]
        ] do
      estimates = PayoutEstimates.variants(money("10000"), type, nil, ~D[2024-03-31])

      assert Enum.map(estimates, & &1.variant) == Keyword.keys(expected)

      for estimate <- estimates do
        assert Money.equal?(estimate.amount, money(Keyword.fetch!(expected, estimate.variant)))
        refute estimate.youth_relief?
      end
    end
  end

  test "uses the student estimate below 26 without removing other matching alternatives" do
    [employee] = PayoutEstimates.variants(money("10000"), :uop, ~D[2000-04-01], ~D[2024-03-31])

    assert Money.equal?(employee.amount, money("7852.39"))
    assert Money.equal?(employee.social, money("1371.00"))
    assert Money.equal?(employee.health, money("776.61"))
    assert Money.equal?(employee.tax, money("0"))
    assert employee.youth_relief?

    estimates = PayoutEstimates.variants(money("10000"), :uz, ~D[2000-04-01], ~D[2024-03-31])

    assert Enum.map(estimates, & &1.variant) == [:uz_student, :uz_health, :uz_social]

    for {estimate, {amount, social, health}} <-
          Enum.zip(estimates, [
            {"10000.00", "0", "0"},
            {"9100.00", "0", "900.00"},
            {"8075.34", "1126.00", "798.66"}
          ]) do
      assert Money.equal?(estimate.amount, money(amount))
      assert Money.equal?(estimate.social, money(social))
      assert Money.equal?(estimate.health, money(health))
      assert Money.equal?(estimate.tax, money("0"))
      assert estimate.youth_relief?
    end
  end

  test "youth PIT includes the 26th birthday but the student alternative does not" do
    gross = money("10000")
    birthday = ~D[1998-03-31]

    assert [%{variant: :uz_student}, _health, _social] =
             PayoutEstimates.variants(gross, :uz, birthday, ~D[2024-03-30])

    on_birthday = PayoutEstimates.variants(gross, :uz, birthday, ~D[2024-03-31])
    assert Enum.map(on_birthday, & &1.variant) == [:uz_health, :uz_social]
    assert Enum.all?(on_birthday, & &1.youth_relief?)

    after_birthday = PayoutEstimates.variants(gross, :uz, birthday, ~D[2024-04-01])
    assert Enum.map(after_birthday, & &1.variant) == [:uz_health, :uz_social]
    refute Enum.any?(after_birthday, & &1.youth_relief?)
  end

  test "youth relief does not apply to specific-task contracts or invent B2B deductions" do
    for {type, expected} <- [
          uod: [uod_20: "9040.00", uod_50: "9400.00"],
          b2b: [b2b: "10000.00"]
        ] do
      estimates = PayoutEstimates.variants(money("10000"), type, ~D[2000-04-01], ~D[2024-03-31])

      for estimate <- estimates do
        assert Money.equal?(estimate.amount, money(Keyword.fetch!(expected, estimate.variant)))
        refute estimate.youth_relief?
      end
    end

    assert PayoutEstimates.variants(money("10000"), nil, nil, ~D[2024-03-31]) == []
  end

  test "closest selects the matching alternative and returns nil without estimates" do
    estimates = PayoutEstimates.variants(money("10000"), :uz, nil, ~D[2024-03-31])

    assert %{variant: :uz_health} = PayoutEstimates.closest(estimates, money("8140"))
    assert PayoutEstimates.closest([], money("8140")) == nil
  end

  test "closest preserves order for numerically equal Decimal distances" do
    first = %{variant: :uz_social, amount: money("10000.0")}
    second = %{variant: :uz_health, amount: money("9999.980")}

    assert PayoutEstimates.closest([first, second], money("9999.99")) == first
    assert PayoutEstimates.closest([second, first], money("9999.99")) == second
  end

  defp money(amount), do: Money.new!(:PLN, amount)
end
