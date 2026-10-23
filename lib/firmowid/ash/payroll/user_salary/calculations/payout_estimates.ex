defmodule Firmowid.Ash.Payroll.UserSalary.Calculations.PayoutEstimates do
  @moduledoc "Estimates common Polish payouts with first-bracket PIT, no PPK and unused annual limits."
  use Ash.Resource.Calculation

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope

  @impl true
  def load(_query, _opts, context) do
    [:member_id, member: [:birthday], monthly_amount: [month: context.arguments.month]]
  end

  @impl true
  def calculate(records, _opts, context) do
    date = Date.end_of_month(context.arguments.month)
    member_ids = Enum.map(records, & &1.member_id)

    contracts =
      %{}
      |> Payroll.list_employment_contracts!(
        query: [
          filter: [
            member_id: [in: member_ids],
            starts_at: [less_than_or_equal: date]
          ],
          sort: [starts_at: :desc]
        ],
        scope: Scope.new!(context.actor, context.tenant)
      )
      |> Enum.group_by(& &1.member_id)

    Enum.map(records, fn salary ->
      contract = contracts |> Map.get(salary.member_id, []) |> List.first()
      type = if contract, do: contract.contract_type
      variants(salary.monthly_amount, type, salary.member.birthday, date)
    end)
  end

  @doc "Uses age to choose the agreed student/health-only estimate, without recording insurance status."
  @spec variants(Money.t(), atom() | nil, Date.t() | nil, Date.t()) :: [map()]
  def variants(gross, type, birthday, date) do
    young? = young?(birthday, date)
    gross = gross |> Money.to_decimal() |> Decimal.round(2, :half_up)

    case type do
      :uop ->
        [estimate(gross, :uop, ["0.0976", "0.015", "0.0245"], :employee, 300, young?)]

      :uz ->
        standard = [
          estimate(gross, :uz_health, [], "0.20", 0, young?),
          estimate(gross, :uz_social, ["0.0976", "0.015"], "0.20", 0, young?)
        ]

        if young? and Date.before?(date, Date.shift(birthday, year: 26)),
          do: [estimate(gross, :uz_student, [], "0.20", 0, true) | standard],
          else: standard

      :uod ->
        [
          estimate(gross, :uod_20, [], "0.20", 0, false),
          estimate(gross, :uod_50, [], "0.50", 0, false)
        ]

      :b2b ->
        [estimate(gross, :b2b, [], "0", 0, false)]

      nil ->
        []
    end
  end

  @doc "Returns the closest hypothetical payout, preserving variant order on equal differences."
  @spec closest([map()], Money.t()) :: map() | nil
  def closest(estimates, amount) do
    amount = amount |> Money.to_decimal() |> Decimal.abs()

    Enum.min_by(
      estimates,
      &Decimal.abs(Decimal.sub(Money.to_decimal(&1.amount), amount)),
      Decimal,
      fn -> nil end
    )
  end

  defp young?(nil, _date), do: false

  defp young?(%Date{} = birthday, date) do
    # End of the work month is a proxy for the unknown payout date.
    Date.compare(date, Date.shift(birthday, year: 26)) != :gt
  end

  defp estimate(gross, variant, social_rates, costs, reduction, youth_relief?) do
    social = Enum.reduce(social_rates, Decimal.new(0), &Decimal.add(&2, percent(gross, &1)))
    base = Decimal.sub(gross, social)
    costs = if costs == :employee, do: Decimal.new(250), else: percent(base, costs)
    taxable = base |> Decimal.sub(costs) |> Decimal.max(0) |> Decimal.round(0, :half_up)

    tax =
      if youth_relief? or variant == :b2b do
        Decimal.new(0)
      else
        taxable
        |> Decimal.mult("0.12")
        |> Decimal.sub(reduction)
        |> Decimal.max(0)
        |> Decimal.round(0, :half_up)
      end

    health =
      if variant in [:uop, :uz_social, :uz_health] do
        health = percent(base, "0.09")

        if variant == :uop do
          # Health insurance is capped by the hypothetical advance under the
          # rules at 31 December 2021 (art. 83 of the health insurance act).
          cap = taxable |> Decimal.mult("0.17") |> Decimal.sub("43.76") |> Decimal.max(0)
          Decimal.min(health, cap)
        else
          health
        end
      else
        Decimal.new(0)
      end

    %{
      variant: variant,
      amount: gross |> Decimal.sub(social) |> Decimal.sub(health) |> Decimal.sub(tax) |> money(),
      social: money(social),
      health: money(health),
      tax: money(tax),
      youth_relief?: youth_relief?
    }
  end

  defp percent(amount, rate), do: amount |> Decimal.mult(rate) |> Decimal.round(2, :half_up)
  defp money(amount), do: Money.new!(:PLN, amount)
end
