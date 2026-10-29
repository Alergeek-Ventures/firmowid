defmodule Firmowid.Payroll.PayoutCalculation do
  @moduledoc """
  Pure, deliberately bounded Polish payroll calculation for payments in 2026.

  Inputs describe one ordinary monthly payment under an active contract. Annual
  social bases include all payers; taxable and PIT-0 exempt income concern this payer.
  Opening balances exclude every income component included in this calculation.
  A missing value never means zero. Unsupported cases never return an estimate.
  """

  alias Decimal, as: D

  @type outcome :: %{
          status: :calculated | :incomplete | :unsupported,
          missing: [atom()],
          unsupported: [atom()],
          result: map() | nil
        }

  @doc """
  Calculates net PLN pay from a declaration and explicitly supplied payroll data.

  `employer_ppk_income` is the actual taxable employer contribution transferred
  in this month on or before payout, not the contribution accrued on the current
  gross payment. A positive amount requires its actual `employer_ppk_date`.
  `student_until` is the last confirmed day of student status. Status or age
  boundaries reached by payout require work-period information and are not
  calculated. PIT-0 other than youth relief, preferential settlement, copyright
  costs and potentially reduced health contributions require separate support.
  PPK rates below 2% require monthly earnings from all sources, which these
  inputs do not establish, and are therefore not calculated.
  """
  @spec calculate(map() | nil, map()) :: outcome()
  def calculate(declaration, inputs) do
    missing = missing_fields(declaration, inputs)
    unsupported = unsupported_cases(declaration, inputs)

    cond do
      unsupported != [] -> outcome(:unsupported, missing, unsupported)
      missing != [] -> outcome(:incomplete, missing, [])
      true -> calculate_complete(declaration, inputs)
    end
  end

  defp missing_fields(declaration, inputs) do
    common = [
      :contract_type,
      :payout_date,
      :gross,
      :employment_active,
      :single_payment,
      :standard_pay
    ]

    missing = absent(inputs, common)

    if is_nil(declaration) do
      missing ++ [:applicable_declaration]
    else
      required = [
        :received_on,
        :applies_from,
        :tax_residency,
        :pit2,
        :pit0,
        :tax_mode,
        :preferential,
        :copyright_costs,
        :ppk
      ]

      missing = missing ++ absent(declaration, required) ++ absent(inputs, [:employer_ppk_income])
      missing = missing ++ declaration_dates(declaration, inputs)
      missing = missing ++ contract_missing(declaration, inputs)
      missing = missing ++ youth_missing(declaration, inputs)
      missing = missing ++ ppk_date_missing(inputs)

      missing =
        if Map.get(declaration, :ppk) == :participant do
          missing ++ absent(declaration, [:ppk_employee_rate])
        else
          missing
        end

      missing =
        if Map.get(declaration, :tax_mode) == :no_advance do
          missing ++ absent(declaration, [:request_year])
        else
          missing
        end

      Enum.uniq(missing)
    end
  end

  defp contract_missing(declaration, %{contract_type: :uop} = inputs) do
    fields =
      if Map.get(declaration, :tax_mode) == :standard, do: [:prior_taxable_income], else: []

    absent(declaration, [:employee_costs, :youth_relief]) ++
      absent(inputs, [:prior_social_base | fields])
  end

  defp contract_missing(declaration, %{contract_type: :uz} = inputs) do
    missing = absent(declaration, [:student, :other_employment, :own_employer, :youth_relief])
    missing = missing ++ absent(inputs, [:insurance_unchanged])
    missing = missing ++ absent(inputs, [:birthday])

    missing =
      if Map.get(declaration, :student) == true and before_26?(inputs) do
        missing ++ absent(declaration, [:student_until])
      else
        missing
      end

    status_known? =
      not is_nil(Map.get(declaration, :student)) and not is_nil(inputs.birthday) and
        (Map.get(declaration, :student) == false or not before_26?(inputs) or
           not is_nil(Map.get(declaration, :student_until)))

    if status_known? and variant(declaration, inputs) == :uz_social do
      missing ++ absent(declaration, [:sickness]) ++ absent(inputs, [:prior_social_base])
    else
      missing
    end
  end

  defp contract_missing(declaration, %{contract_type: :uod}), do: absent(declaration, [:own_employer])

  defp contract_missing(_declaration, _inputs), do: []

  defp youth_missing(declaration, inputs) do
    if inputs.contract_type in [:uop, :uz] and Map.get(declaration, :youth_relief) == :apply do
      absent(inputs, [:birthday]) ++
        if youth_age?(inputs), do: absent(inputs, [:prior_exempt_income]), else: []
    else
      []
    end
  end

  defp absent(map, fields), do: Enum.filter(fields, &is_nil(Map.get(map, &1)))

  defp ppk_date_missing(%{employer_ppk_income: %D{} = amount} = inputs) do
    if D.compare(amount, 0) == :gt, do: absent(inputs, [:employer_ppk_date]), else: []
  end

  defp ppk_date_missing(_inputs), do: []

  defp declaration_dates(declaration, %{payout_date: %Date{} = date}) do
    future? =
      Enum.any?([Map.get(declaration, :applies_from), Map.get(declaration, :received_on)], fn
        %Date{} = from -> Date.after?(from, date)
        nil -> false
      end)

    if future?, do: [:applicable_declaration], else: []
  end

  defp declaration_dates(_declaration, _inputs), do: []

  defp unsupported_cases(declaration, inputs) do
    []
    |> flag(inputs.contract_type == :b2b, :b2b_taxation)
    |> flag(
      not is_nil(inputs.contract_type) and inputs.contract_type not in [:uop, :uz, :uod, :b2b],
      :contract_type
    )
    |> flag(match?(%Date{year: year} when year != 2026, inputs.payout_date), :tax_year)
    |> flag(inputs.employment_active == false, :inactive_contract)
    |> flag(inputs.single_payment == false, :multiple_payments)
    |> flag(inputs.standard_pay == false, :nonstandard_pay)
    |> flag(future_birthday?(inputs), :birthday)
    |> flag(invalid_ppk_date?(inputs), :ppk_transfer_timing)
    |> flag(
      inputs.contract_type == :uz and inputs[:insurance_unchanged] == false,
      :insurance_status_change
    )
    |> flag(negative_inputs?(inputs), :negative_inputs)
    |> declaration_unsupported(declaration, inputs)
  end

  defp declaration_unsupported(reasons, nil, _inputs), do: reasons

  defp declaration_unsupported(reasons, declaration, inputs) do
    reasons
    |> flag(Map.get(declaration, :tax_residency) == :other, :foreign_tax_residency)
    |> flag(Map.get(declaration, :pit0) in [:returning, :family, :senior], :pit0)
    |> flag(
      Map.get(declaration, :preferential) in [
        :joint_below,
        :joint_above,
        :single_below,
        :single_above
      ],
      :preferential
    )
    |> flag(Map.get(declaration, :copyright_costs) == true, :copyright_costs)
    |> flag(Map.get(declaration, :tax_mode) == :no_advance, :no_advance)
    |> flag(
      inputs.contract_type in [:uz, :uod] and Map.get(declaration, :own_employer) == true,
      :own_employer
    )
    |> flag(
      inputs.contract_type == :uz and Map.get(declaration, :other_employment) == :other,
      :other_employment
    )
    |> flag(small_civil_payment?(inputs), :small_civil_contract)
    |> flag(student_change?(declaration, inputs), :student_status_change)
    |> flag(ineligible_ppk?(declaration, inputs), :ppk_eligibility)
    |> flag(invalid_ppk_rate?(declaration), :ppk_employee_rate)
    |> flag(uncertain_ppk_timing?(declaration, inputs), :exempt_social_allocation)
    |> flag(reduced_ppk_rate?(declaration), :reduced_ppk_rate)
  end

  defp flag(reasons, true, reason), do: reasons ++ [reason]
  defp flag(reasons, false, _reason), do: reasons

  defp negative_inputs?(inputs) do
    Enum.any?(
      [
        :gross,
        :prior_taxable_income,
        :prior_social_base,
        :prior_exempt_income,
        :employer_ppk_income
      ],
      fn field ->
        not is_nil(inputs[field]) and D.compare(inputs[field], 0) == :lt
      end
    )
  end

  defp future_birthday?(%{birthday: %Date{} = birthday, payout_date: %Date{} = payout_date}),
    do: Date.after?(birthday, payout_date)

  defp future_birthday?(_inputs), do: false

  defp invalid_ppk_date?(%{
         employer_ppk_income: %D{} = amount,
         employer_ppk_date: %Date{} = ppk_date,
         payout_date: %Date{} = payout_date
       }) do
    D.compare(amount, 0) == :gt and
      (Date.after?(ppk_date, payout_date) or
         Date.beginning_of_month(ppk_date) != Date.beginning_of_month(payout_date))
  end

  defp invalid_ppk_date?(_inputs), do: false

  defp small_civil_payment?(%{contract_type: type, gross: %D{} = gross}) when type in [:uz, :uod] do
    D.compare(gross, 0) == :gt and D.compare(gross, 200) != :gt
  end

  defp small_civil_payment?(_inputs), do: false

  defp invalid_ppk_rate?(%{ppk: :participant, ppk_employee_rate: %D{} = rate}) do
    D.compare(rate, "0.5") == :lt or D.compare(rate, 4) == :gt
  end

  defp invalid_ppk_rate?(_declaration), do: false

  defp reduced_ppk_rate?(%{ppk: :participant, ppk_employee_rate: %D{} = rate}) do
    D.compare(rate, "0.5") != :lt and D.compare(rate, 2) == :lt
  end

  defp reduced_ppk_rate?(_declaration), do: false

  defp ineligible_ppk?(declaration, inputs) do
    (Map.get(declaration, :ppk) == :participant and
       variant(declaration, inputs) in [:uod_20, :uz_student, :uz_health]) or
      (inputs.contract_type == :uod and not is_nil(inputs.employer_ppk_income) and
         D.compare(inputs.employer_ppk_income, 0) == :gt)
  end

  defp student_change?(declaration, %{contract_type: :uz, payout_date: %Date{} = date} = inputs) do
    if Map.get(declaration, :student) == true do
      # Insurance status concerns the work period, not merely the payment date.
      # Without period-level data, an expired student declaration is insufficient
      # even when the expiry happened before the month of payment.
      Enum.any?([Map.get(declaration, :student_until), birthday_26(inputs)], fn
        %Date{} = change ->
          Date.compare(change, date) != :gt

        nil ->
          false
      end)
    else
      false
    end
  end

  defp student_change?(_declaration, _inputs), do: false

  defp uncertain_ppk_timing?(
         declaration,
         %{payout_date: %Date{} = date, employer_ppk_date: %Date{} = ppk_date, employer_ppk_income: %D{} = income} =
           inputs
       ) do
    birthday = birthday_26(inputs)

    Map.get(declaration, :youth_relief) == :apply and inputs.contract_type in [:uop, :uz] and
      D.compare(income, 0) == :gt and not is_nil(birthday) and
      Date.compare(ppk_date, birthday) != :gt != (Date.compare(date, birthday) != :gt)
  end

  defp uncertain_ppk_timing?(_declaration, _inputs), do: false

  defp variant(_declaration, %{contract_type: :uop}), do: :uop
  defp variant(_declaration, %{contract_type: :uod}), do: :uod_20

  defp variant(declaration, %{contract_type: :uz} = inputs) do
    cond do
      student_exempt?(declaration, inputs) -> :uz_student
      Map.get(declaration, :other_employment) == :at_least_minimum -> :uz_health
      Map.get(declaration, :other_employment) in [:none, :below_minimum] -> :uz_social
      true -> nil
    end
  end

  defp variant(_declaration, _inputs), do: nil

  defp student_exempt?(declaration, inputs) do
    Map.get(declaration, :student) == true and before_26?(inputs) and
      match?(%Date{}, Map.get(declaration, :student_until)) and
      Date.compare(Map.get(declaration, :student_until), inputs.payout_date) != :lt
  end

  defp before_26?(inputs) do
    not is_nil(birthday_26(inputs)) and not is_nil(inputs.payout_date) and
      Date.before?(inputs.payout_date, birthday_26(inputs))
  end

  defp youth_age?(inputs) do
    not is_nil(birthday_26(inputs)) and not is_nil(inputs.payout_date) and
      Date.compare(inputs.payout_date, birthday_26(inputs)) != :gt
  end

  defp birthday_26(%{birthday: %Date{} = birthday}), do: Date.shift(birthday, year: 26)
  defp birthday_26(_inputs), do: nil

  defp calculate_complete(declaration, inputs) do
    variant = variant(declaration, inputs)
    social = social(declaration, inputs, variant, inputs.gross)
    income = D.add(inputs.gross, inputs.employer_ppk_income)
    exempt = exempt_income(declaration, inputs, income)

    if uncertain_exempt_allocation?(inputs, income, exempt, variant) do
      outcome(:unsupported, [], [:exempt_social_allocation])
    else
      deductible_social = deductible_social(declaration, inputs, variant, social, income, exempt)
      taxable_income = income |> D.sub(exempt) |> D.sub(deductible_social) |> positive()
      costs = costs(declaration, variant, taxable_income, D.sub(income, exempt), exempt)
      taxable = taxable_income |> D.sub(costs) |> positive() |> D.round(0, :half_up)
      tax = tax(declaration, inputs, variant, taxable)
      health = health(inputs, variant, social)

      ppk =
        if declaration.ppk == :participant,
          do: percent(inputs.gross, declaration.ppk_employee_rate),
          else: D.new(0)

      amount = inputs.gross |> D.sub(social) |> D.sub(health) |> D.sub(tax) |> D.sub(ppk)

      cond do
        health_cap_possible?(inputs, variant, social, health) ->
          outcome(:unsupported, [], [:health_contribution_cap])

        D.compare(amount, 0) == :lt ->
          outcome(:unsupported, [], [:negative_payout])

        true ->
          result =
            Map.new(
              %{
                amount: amount,
                gross: inputs.gross,
                social: social,
                health: health,
                tax: tax,
                ppk: ppk,
                costs: costs,
                taxable: taxable
              },
              fn {key, amount} ->
                {key, Money.new(:PLN, D.round(amount, 2, :half_up))}
              end
            )

          %{
            status: :calculated,
            missing: [],
            unsupported: [],
            result: Map.merge(result, %{variant: variant, youth_relief?: D.compare(exempt, 0) == :gt})
          }
      end
    end
  end

  defp social(declaration, inputs, variant, gross) when variant in [:uop, :uz_social] do
    pension_base = D.min(gross, 282_600 |> D.sub(inputs.prior_social_base) |> positive())
    sickness_base = if variant == :uop, do: gross, else: D.min(gross, 23_550)

    sickness =
      if variant == :uop or declaration.sickness,
        do: percent(sickness_base, "2.45"),
        else: D.new(0)

    pension_base |> percent("9.76") |> D.add(percent(pension_base, "1.5")) |> D.add(sickness)
  end

  defp social(_declaration, _inputs, _variant, _gross), do: D.new(0)

  defp exempt_income(declaration, inputs, income) do
    if inputs.contract_type in [:uop, :uz] and declaration.youth_relief == :apply and
         youth_age?(inputs) do
      D.min(income, 85_528 |> D.sub(inputs.prior_exempt_income) |> positive())
    else
      D.new(0)
    end
  end

  defp uncertain_exempt_allocation?(inputs, income, exempt, variant) do
    partial? = D.compare(exempt, 0) == :gt and D.compare(exempt, income) == :lt

    partial? and
      (D.compare(inputs.employer_ppk_income, 0) == :gt or
         (variant in [:uop, :uz_social] and
            D.compare(D.add(inputs.prior_social_base, inputs.gross), 282_600) == :gt) or
         (variant == :uz_social and D.compare(inputs.gross, 23_550) == :gt))
  end

  defp deductible_social(declaration, inputs, variant, social, income, exempt) do
    cond do
      D.compare(exempt, 0) == :eq -> social
      D.compare(exempt, income) == :eq -> D.new(0)
      true -> social |> D.sub(social(declaration, inputs, variant, exempt)) |> positive()
    end
  end

  defp costs(declaration, :uop, _income, revenue, exempt) do
    fixed =
      case declaration.employee_costs do
        :none -> 0
        :standard -> 250
        :elevated -> 300
      end

    if D.compare(exempt, 0) == :gt, do: D.min(revenue, fixed), else: D.new(fixed)
  end

  defp costs(_declaration, _variant, income, _revenue, _exempt), do: percent(income, 20)

  defp tax(declaration, inputs, variant, taxable) do
    advance =
      cond do
        declaration.tax_mode == :higher ->
          D.mult(taxable, "0.32")

        variant != :uop ->
          D.mult(taxable, "0.12")

        true ->
          lower = D.min(taxable, 120_000 |> D.sub(inputs.prior_taxable_income) |> positive())
          D.add(D.mult(lower, "0.12"), D.mult(D.sub(taxable, lower), "0.32"))
      end

    reduction =
      case declaration.pit2 do
        :none -> 0
        :one_twelfth -> 300
        :one_twenty_fourth -> 150
        :one_thirty_sixth -> 100
      end

    advance |> D.sub(reduction) |> positive() |> D.round(0, :half_up)
  end

  defp health(inputs, variant, social) when variant in [:uop, :uz_social, :uz_health] do
    inputs.gross |> D.sub(social) |> percent(9)
  end

  defp health(_inputs, _variant, _social), do: D.new(0)

  defp health_cap_possible?(inputs, variant, social, health) when variant in [:uop, :uz_social, :uz_health] do
    base = D.sub(inputs.gross, social)

    # Art. 83 uses the hypothetical 2021 advance, not today's PIT-2 reduction.
    # This lower bound proves that the cap cannot apply, without inventing a
    # historical PIT-2 election (in particular for today's split PIT-2). Where
    # it cannot prove that, return unsupported instead of charging the full 9%.
    lower_bound =
      if variant == :uop do
        base
        |> D.sub(300)
        |> positive()
        |> D.round(0, :half_up)
        |> D.mult("0.17")
        |> D.sub("43.76")
        |> positive()
      else
        base |> D.sub(percent(base, 20)) |> positive() |> D.round(0, :half_up) |> D.mult("0.17")
      end

    D.compare(health, lower_bound) == :gt
  end

  defp health_cap_possible?(_inputs, _variant, _social, _health), do: false

  defp percent(amount, rate), do: amount |> D.mult(rate) |> D.div(100) |> D.round(2, :half_up)
  defp positive(amount), do: D.max(amount, 0)

  defp outcome(status, missing, unsupported) do
    %{status: status, missing: missing, unsupported: unsupported, result: nil}
  end
end
