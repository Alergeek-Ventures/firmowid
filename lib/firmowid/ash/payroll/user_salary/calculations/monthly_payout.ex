defmodule Firmowid.Ash.Payroll.UserSalary.Calculations.MonthlyPayout do
  @moduledoc "Calculates monthly net pay from applicable declarations and explicitly sourced payroll facts."

  use Ash.Resource.Calculation

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.MemberPayrollInput
  alias Firmowid.Ash.Payroll.PayoutCalculation
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker

  @impl true
  def load(_query, _opts, _context) do
    [
      :id,
      :member_id,
      :hourly_rate,
      :starts_at,
      :employment_contract_id,
      member: [:birthday]
    ]
  end

  @impl true
  def calculate([], _opts, _context), do: []

  def calculate(records, _opts, context) do
    month = Date.beginning_of_month(context.arguments.month)
    member_ids = records |> Enum.map(& &1.member_id) |> Enum.uniq()
    scope = Scope.new!(context.actor, context.tenant)
    month_start = DateTime.new!(month, ~T[00:00:00], "Etc/UTC")

    next_month_start =
      DateTime.new!(Date.add(Date.end_of_month(month), 1), ~T[00:00:00], "Etc/UTC")

    monthly_inputs =
      MemberPayrollInput.list!(%{salary_month: month},
        query: [filter: [member_id: [in: member_ids]]],
        scope: scope
      )

    inputs_by_member = Map.new(monthly_inputs, &{&1.member_id, &1})

    declarations =
      %{}
      |> Payroll.list_tax_declarations!(
        query: [filter: [member_id: [in: member_ids]]],
        scope: scope
      )
      |> Enum.group_by(& &1.member_id)

    contracts =
      Payroll.list_employment_contracts!(%{},
        query: [
          filter: [
            member_id: [in: member_ids],
            starts_at: [less_than_or_equal: Date.end_of_month(month)]
          ],
          sort: [starts_at: :desc]
        ],
        scope: scope
      )

    contracts_by_id = Map.new(contracts, &{&1.id, &1})
    contracts_by_member = Enum.group_by(contracts, & &1.member_id)

    rates_by_member =
      %{}
      |> Payroll.list_salaries!(
        query: [
          filter: [member_id: [in: member_ids], starts_at: [less_than: next_month_start]],
          sort: [starts_at: :desc]
        ],
        scope: scope
      )
      |> Enum.group_by(& &1.member_id)

    hours_by_member =
      %{month: month.month, year: month.year}
      |> Timetracker.list_hours_records!(
        query: [filter: [member_id: [in: member_ids]]],
        scope: scope
      )
      |> Enum.group_by(& &1.member_id)

    Enum.map(records, fn salary ->
      monthly_input = Map.get(inputs_by_member, salary.member_id)
      contract = contracts_by_member |> Map.get(salary.member_id, []) |> List.first()
      {payout_date, payout_date_basis} = payout_date(monthly_input, contract, month)

      declaration =
        effective_declaration(
          Map.get(declarations, salary.member_id, []),
          payout_date
        )

      {gross, gross_missing, gross_unsupported} =
        resolve_gross(
          field(monthly_input, :gross),
          salary,
          Map.get(rates_by_member, salary.member_id, []),
          Map.get(contracts_by_id, field(salary, :employment_contract_id)),
          Map.get(hours_by_member, salary.member_id, []),
          month_start,
          next_month_start
        )

      inputs = %{
        contract_type: field(contract, :contract_type),
        payout_date: payout_date,
        gross: decimal_amount(gross),
        employment_active: employment_active(contract, payout_date),
        single_payment: field(monthly_input, :single_payment),
        standard_pay: field(monthly_input, :standard_pay),
        insurance_unchanged: field(monthly_input, :insurance_unchanged),
        employer_ppk_date: field(monthly_input, :employer_ppk_date),
        employer_ppk_income: field(monthly_input, :employer_ppk_income),
        prior_taxable_income: field(monthly_input, :prior_taxable_income),
        prior_social_base: field(monthly_input, :prior_social_base),
        prior_exempt_income: field(monthly_input, :prior_exempt_income),
        birthday: salary.member.birthday
      }

      outcome =
        declaration
        |> PayoutCalculation.calculate(inputs)
        |> add_source_reasons(
          gross_missing ++ payout_date_missing(payout_date, payout_date_basis),
          gross_unsupported
        )

      Map.merge(outcome, %{
        month: month,
        payout_date: payout_date,
        payout_date_basis: payout_date_basis,
        gross: gross,
        gross_source: gross_source(monthly_input, gross)
      })
    end)
  end

  defp effective_declaration(_declarations, nil), do: nil

  defp effective_declaration(declarations, %Date{} = payout_date) do
    Enum.find(declarations, fn declaration ->
      declaration.applies_from && declaration.received_on &&
        Date.compare(declaration.applies_from, payout_date) != :gt
    end)
  end

  defp payout_date(%{payout_date: %Date{} = date, payout_date_basis: basis}, _contract, _month), do: {date, basis}

  defp payout_date(_input, %{payout_day: day, payout_month_offset: offset}, month)
       when is_integer(day) and is_integer(offset) do
    payment_month = Date.shift(month, month: offset)

    case Date.new(payment_month.year, payment_month.month, day) do
      {:ok, date} -> {date, :planned}
      {:error, :invalid_date} -> {nil, nil}
    end
  end

  defp payout_date(_input, _contract, _month), do: {nil, nil}

  defp resolve_gross(%Decimal{} = gross, _salary, _rates, _contract, _hours, _month_start, _next_month_start),
    do: {Money.new!(:PLN, gross), [], []}

  defp resolve_gross(nil, salary, rates, contract, hours, month_start, next_month_start) do
    full_month_rate = rate_for_whole_month(rates, month_start)

    cond do
      rate_changed_during_month?(rates, month_start, next_month_start) ->
        {nil, [], [:rate_change]}

      non_pln_contract_salary?(contract) ->
        {nil, [], [:currency]}

      hours == [] ->
        {nil, [:gross, :hours_record], []}

      is_nil(full_month_rate) ->
        {nil, [:gross], []}

      full_month_rate.id != salary.id ->
        {nil, [:gross], []}

      not confirmed_rate?(salary, contract) ->
        {nil, [:gross], []}

      true ->
        [hours_record] = hours

        gross =
          salary.hourly_rate
          |> Decimal.mult(hours_record.number_of_hours)
          |> Decimal.round(2, :half_up)

        {Money.new!(:PLN, gross), [], []}
    end
  end

  defp rate_changed_during_month?(rates, month_start, next_month_start) do
    Enum.any?(rates, fn rate ->
      DateTime.after?(rate.starts_at, month_start) and
        DateTime.before?(rate.starts_at, next_month_start)
    end)
  end

  defp rate_for_whole_month(rates, month_start) do
    Enum.find(rates, &(DateTime.compare(&1.starts_at, month_start) != :gt))
  end

  defp confirmed_rate?(salary, nil), do: is_nil(field(salary, :employment_contract_id))

  defp confirmed_rate?(salary, contract) do
    is_nil(field(salary, :employment_contract_id)) or
      Map.get(contract, :hourly_rate_confirmed) == true
  end

  defp non_pln_contract_salary?(%{salary: %Money{} = contract_salary}),
    do: Money.to_currency_code(contract_salary) != :PLN

  defp non_pln_contract_salary?(_contract), do: false

  defp employment_active(%{status: :active, starts_at: starts_at}, %Date{} = payout_date),
    do: Date.compare(starts_at, payout_date) != :gt

  defp employment_active(%{status: status}, _date) when status != :active, do: false
  defp employment_active(_contract, _date), do: nil

  defp payout_date_missing(%Date{}, nil), do: [:payout_date_basis]

  defp payout_date_missing(_date, _basis), do: []

  defp decimal_amount(%Money{} = money), do: Money.to_decimal(money)
  defp decimal_amount(nil), do: nil

  defp gross_source(_input, nil), do: nil
  defp gross_source(%{gross: %Decimal{}}, _gross), do: :payroll_data
  defp gross_source(_input, %Money{}), do: :timesheet

  defp add_source_reasons(outcome, missing, unsupported) do
    missing = Enum.uniq(outcome.missing ++ missing)
    unsupported = Enum.uniq(outcome.unsupported ++ unsupported)

    status =
      cond do
        unsupported != [] -> :unsupported
        missing != [] -> :incomplete
        true -> outcome.status
      end

    %{
      outcome
      | status: status,
        missing: missing,
        unsupported: unsupported,
        result: if(status == :calculated, do: outcome.result)
    }
  end

  defp field(nil, _field), do: nil
  defp field(record, field), do: Map.get(record, field)
end
