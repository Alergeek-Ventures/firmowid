defmodule Firmowid.Ash.Payroll.UserSalary.Calculations.PayoutEstimates do
  @moduledoc """
  Estimates Polish payouts from current profiles or hypothetical contract variants.

  Uses first-bracket PIT, no PPK and assumes unused annual limits: it does not
  accumulate the PLN 85,528 youth exemption, copyright costs or social bases.
  A profile is current, even when forecasting a past month. Month-end proxies
  the unknown payout date; this is not a payroll or annual tax settlement.

  For the UOP health cap, a positive current PIT-2 reduction assumes eligibility
  for the full PLN 43.76 reduction under 2021 rules; zero assumes none. The
  profile does not establish the separate 2021 eligibility conditions. Current
  PLN 100/150 reductions do not proportionally split that historical amount.
  This assumption can materially affect low payouts, including profile-based ones.
  """
  use Ash.Resource.Calculation

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope

  @impl true
  def load(_query, _opts, context) do
    [
      :member_id,
      member: [:birthday, :tax_profile],
      monthly_amount: [month: context.arguments.month]
    ]
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

      variants(
        salary.monthly_amount,
        type,
        salary.member.birthday,
        date,
        salary.member.tax_profile
      )
    end)
  end

  @doc "Uses a complete contract-specific profile, otherwise returns hypothetical contract variants."
  @spec variants(Money.t(), atom() | nil, Date.t() | nil, Date.t(), map() | nil) :: [map()]
  def variants(gross, type, birthday, date, profile) do
    case profile_assumptions(type, birthday, date, profile) do
      {variant, rates, costs, reduction, relief?} ->
        gross = gross |> Money.to_decimal() |> Decimal.round(2, :half_up)

        [
          gross
          |> estimate(variant, rates, costs, reduction, relief?)
          |> Map.put(:basis, :profile)
        ]

      nil ->
        variants(gross, type, birthday, date)
    end
  end

  defp profile_assumptions(:uop, birthday, date, %{
         monthly_tax_reduction: reduction,
         employment_costs: costs,
         youth_relief: relief
       })
       when reduction in [0, 100, 150, 300] and costs in [:none, :standard, :increased] and
              relief in [:automatic, :disabled] do
    if relief == :disabled or not is_nil(birthday) do
      costs = %{none: 0, standard: 250, increased: 300}[costs]

      {:uop, ["0.0976", "0.015", "0.0245"], costs, reduction, relief == :automatic and young?(birthday, date)}
    end
  end

  defp profile_assumptions(:uz, birthday, date, %{
         monthly_tax_reduction: reduction,
         mandate_insurance: insurance,
         civil_costs: costs,
         youth_relief: relief
       })
       when reduction in [0, 100, 150, 300] and insurance in [:student, :health, :social, :social_with_sickness] and
              costs in [:standard_20, :copyright_50] and relief in [:automatic, :disabled] do
    if relief == :disabled or not is_nil(birthday) do
      case mandate_contributions(insurance, birthday, date) do
        {variant, rates} ->
          {variant, rates, civil_costs(costs), reduction, relief == :automatic and young?(birthday, date)}

        nil ->
          nil
      end
    end
  end

  defp profile_assumptions(:uod, _birthday, _date, %{monthly_tax_reduction: reduction, civil_costs: costs})
       when reduction in [0, 100, 150, 300] and costs in [:standard_20, :copyright_50] do
    variant = if costs == :standard_20, do: :uod_20, else: :uod_50
    {variant, [], civil_costs(costs), reduction, false}
  end

  defp profile_assumptions(_type, _birthday, _date, _profile), do: nil

  defp mandate_contributions(:student, nil, _date), do: nil

  defp mandate_contributions(:student, birthday, date) do
    if Date.before?(date, Date.shift(birthday, year: 26)), do: {:uz_student, []}
  end

  defp mandate_contributions(:health, _birthday, _date), do: {:uz_health, []}
  defp mandate_contributions(:social, _birthday, _date), do: {:uz_social, ["0.0976", "0.015"]}

  defp mandate_contributions(:social_with_sickness, _birthday, _date),
    do: {:uz_social_with_sickness, ["0.0976", "0.015", "0.0245"]}

  defp civil_costs(:standard_20), do: "0.20"
  defp civil_costs(:copyright_50), do: "0.50"

  @doc "Uses age to choose the agreed student/health-only estimate, without recording insurance status."
  @spec variants(Money.t(), atom() | nil, Date.t() | nil, Date.t()) :: [map()]
  def variants(gross, type, birthday, date) do
    young? = young?(birthday, date)
    gross = gross |> Money.to_decimal() |> Decimal.round(2, :half_up)

    case type do
      :uop ->
        [estimate(gross, :uop, ["0.0976", "0.015", "0.0245"], 250, 300, young?)]

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

  @doc "Returns the closest estimated payout, preserving variant order on equal differences."
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

    costs =
      case costs do
        fixed when is_integer(fixed) -> Decimal.new(fixed)
        rate -> percent(base, rate)
      end

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
      if variant in [:uop, :uz_social, :uz_social_with_sickness, :uz_health] do
        health = percent(base, "0.09")

        if variant == :uop do
          # Health insurance is capped by the hypothetical advance under the
          # rules at 31 December 2021 (art. 83 of the health insurance act).
          # https://isap.sejm.gov.pl/isap.nsf/download.xsp/WDU20042102135/U/D20042135Lj.pdf
          # Current PIT-2 is only a proxy for the separate 2021 eligibility:
          # https://www.gov.pl/web/finanse/przewodnik-po-pit-2
          # Positive reductions assume the full historical amount, not 1/2 or 1/3.
          historical_reduction = if reduction == 0, do: "0", else: "43.76"

          cap =
            taxable
            |> Decimal.mult("0.17")
            |> Decimal.sub(historical_reduction)
            |> Decimal.max(0)

          Decimal.min(health, cap)
        else
          health
        end
      else
        Decimal.new(0)
      end

    %{
      variant: variant,
      basis: :hypothetical,
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
