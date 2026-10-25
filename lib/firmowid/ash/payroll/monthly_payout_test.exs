defmodule Firmowid.Ash.Payroll.MonthlyPayoutTest do
  @moduledoc "Checks automatic payroll amounts and the completeness of their source facts."
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.MemberPayrollInput
  alias Firmowid.Ash.Payroll.MemberTaxDeclaration
  alias Firmowid.Ash.Payroll.UserEmploymentContract
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker.HoursRecord

  setup do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)
    organization_id = admin.member.organization_id

    %{
      admin: admin,
      employee: employee,
      organization_id: organization_id,
      scope: %Scope{actor: admin, tenant: organization_id},
      processor_scope: processor_scope(organization_id)
    }
  end

  test "calculates a complete monthly payout from its declaration and sourced facts", %{
    employee: employee,
    organization_id: organization_id,
    scope: scope
  } do
    month = ~D[2026-01-01]
    payout_date = ~D[2026-02-02]

    contract_fixture!(employee, organization_id, %{
      starts_at: ~D[2025-12-01],
      status: :active,
      contract_type: :uop,
      payout_day: 10,
      payout_month_offset: 1
    })

    declaration_fixture!(employee, scope, %{
      received_on: ~D[2026-01-01],
      applies_from: ~D[2026-01-01],
      pit2: :one_twelfth
    })

    monthly_input =
      monthly_input!(employee, scope, %{
        salary_month: month,
        payout_date: payout_date,
        payout_date_basis: :actual,
        gross: Decimal.new("6000"),
        prior_taxable_income: Decimal.new("0"),
        prior_social_base: Decimal.new("0"),
        prior_exempt_income: Decimal.new("0"),
        employer_ppk_income: Decimal.new("0"),
        single_payment: true,
        standard_pay: true
      })

    calculation = monthly_payout!(employee, scope, month)

    assert calculation.status == :calculated
    assert calculation.month == month
    assert calculation.payout_date == payout_date
    assert calculation.payout_date_basis == :actual
    assert Decimal.equal?(Money.to_decimal(calculation.gross), Decimal.new("6000"))

    assert Decimal.equal?(
             Money.to_decimal(calculation.result.amount),
             Decimal.new("4420.43")
           )

    MemberPayrollInput.update!(monthly_input, %{payout_date: nil, payout_date_basis: nil}, scope: scope)

    planned = monthly_payout!(employee, scope, month)
    assert planned.status == :calculated
    assert planned.payout_date == ~D[2026-02-10]
    assert planned.payout_date_basis == :planned
    assert Money.equal?(planned.result.amount, calculation.result.amount)
  end

  test "does not calculate without a payout date or required opening balances", %{
    employee: employee,
    organization_id: organization_id,
    scope: scope
  } do
    month = ~D[2026-01-01]

    contract_fixture!(employee, organization_id, %{
      starts_at: ~D[2025-12-01],
      status: :active,
      contract_type: :uop
    })

    declaration_fixture!(employee, scope, %{
      received_on: ~D[2026-01-01],
      applies_from: ~D[2026-01-01],
      pit2: :one_twelfth
    })

    {:ok, monthly_input} =
      month
      |> monthly_facts(employee.member.id)
      |> Map.merge(%{payout_date: nil, gross: nil})
      |> MemberPayrollInput.create(scope: scope)

    without_date = monthly_payout!(employee, scope, month)

    assert without_date.result == nil
    assert without_date.gross == nil
    assert :payout_date in without_date.missing
    assert :applicable_declaration in without_date.missing
    assert :hours_record in without_date.missing

    {:ok, monthly_input} =
      MemberPayrollInput.update(monthly_input, %{payout_date: ~D[2026-02-02]}, scope: scope)

    {:ok, _monthly_input} =
      MemberPayrollInput.update(
        monthly_input,
        %{prior_social_base: nil, prior_taxable_income: nil},
        scope: scope
      )

    without_balances = monthly_payout!(employee, scope, month)

    assert without_balances.result == nil
    assert :prior_social_base in without_balances.missing
    assert :prior_taxable_income in without_balances.missing
  end

  test "document imports preserve known values and retain explicit zero and false", %{
    employee: employee,
    organization_id: organization_id,
    scope: scope,
    processor_scope: processor_scope
  } do
    month = ~D[2026-01-01]
    source_blob = blob_fixture!(organization_id)

    {:ok, existing} =
      month
      |> monthly_facts(employee.member.id)
      |> Map.merge(%{
        payout_date: ~D[2026-02-02],
        gross: Decimal.new("1000"),
        prior_taxable_income: Decimal.new("9000"),
        single_payment: true,
        source_blob_id: source_blob.id
      })
      |> MemberPayrollInput.create(scope: scope)

    {:ok, imported} =
      MemberPayrollInput.import_from_document(
        %{
          member_id: employee.member.id,
          salary_month: month,
          source_blob_id: nil,
          payout_date: nil,
          gross: Decimal.new("0"),
          prior_taxable_income: nil,
          single_payment: false
        },
        scope: processor_scope
      )

    assert imported.id == existing.id
    assert imported.payout_date == ~D[2026-02-02]
    assert Decimal.equal?(imported.gross, Decimal.new("0"))
    assert Decimal.equal?(imported.prior_taxable_income, Decimal.new("9000"))
    assert imported.single_payment == false
    assert imported.source_blob_id == source_blob.id

    for missing_member <- [nil, ""] do
      assert {:error, _} =
               MemberPayrollInput.import_from_document(
                 %{member_id: missing_member, salary_month: month, gross: Decimal.new(9999)},
                 scope: processor_scope
               )
    end

    [unchanged] =
      MemberPayrollInput.list!(%{member_id: employee.member.id, salary_month: month},
        scope: scope
      )

    assert Decimal.equal?(unchanged.gross, Decimal.new(0))
  end

  test "uses submitted hours rather than silently treating missing sessions as zero", %{
    employee: employee,
    organization_id: organization_id,
    scope: scope
  } do
    month = ~D[2026-01-01]
    salary = contract_fixture!(employee, organization_id, %{})
    Ash.Seed.update!(salary, %{hourly_rate: Decimal.new("100.0001")})
    declaration_fixture!(employee, scope, %{})

    MemberPayrollInput.create!(Map.put(monthly_facts(month, employee.member.id), :gross, nil),
      scope: scope
    )

    hours =
      Ash.Seed.seed!(HoursRecord, %{
        member_id: employee.member.id,
        organization_id: organization_id,
        blob_id: blob_fixture!(organization_id).id,
        month: 1,
        year: 2026,
        number_of_hours: 60,
        submission_status: :submitted
      })

    calculation = monthly_payout!(employee, scope, month)
    assert calculation.status == :calculated
    assert Money.equal?(calculation.gross, Money.new!(:PLN, "6000.01"))
    assert Money.equal?(calculation.result.amount, Money.new!(:PLN, "4420.44"))

    Ash.Seed.update!(hours, %{submission_status: :withdrawn})
    calculation = monthly_payout!(employee, scope, month)
    assert calculation.result == nil
    assert :hours_record in calculation.missing
  end

  defp monthly_payout!(employee, scope, month) do
    [salary] =
      Payroll.list_salaries!(%{active_at: Date.end_of_month(month)},
        query: [filter: [member_id: [in: [employee.member.id]]]],
        load: [monthly_payout: [month: month]],
        scope: scope
      )

    salary.monthly_payout
  end

  defp monthly_input!(employee, scope, attrs) do
    attrs
    |> Map.put_new(:member_id, employee.member.id)
    |> MemberPayrollInput.create!(scope: scope)
  end

  defp monthly_facts(month, member_id) do
    %{
      member_id: member_id,
      salary_month: month,
      payout_date: ~D[2026-02-02],
      payout_date_basis: :actual,
      gross: Decimal.new("6000"),
      prior_taxable_income: Decimal.new("0"),
      prior_social_base: Decimal.new("0"),
      prior_exempt_income: Decimal.new("0"),
      employer_ppk_income: Decimal.new("0"),
      single_payment: true,
      standard_pay: true
    }
  end

  defp declaration_fixture!(employee, scope, attrs) do
    MemberTaxDeclaration.create_tax_declaration!(
      Map.merge(
        %{
          member_id: employee.member.id,
          received_on: ~D[2026-01-01],
          applies_from: ~D[2026-01-01],
          tax_residency: :poland,
          pit2: :one_twelfth,
          employee_costs: :standard,
          youth_relief: :waived,
          pit0: :none,
          tax_mode: :standard,
          preferential: :none,
          copyright_costs: false,
          ppk: :none
        },
        attrs
      ),
      scope: scope
    )
  end

  defp contract_fixture!(employee, organization_id, attrs) do
    blob = blob_fixture!(organization_id)

    Ash.Seed.seed!(
      UserEmploymentContract,
      Map.merge(
        %{
          organization_id: organization_id,
          member_id: employee.member.id,
          starts_at: ~D[2025-12-01],
          salary: Money.new!(:PLN, Decimal.new("100")),
          blob_id: blob.id,
          status: :active,
          contract_type: :uop
        },
        attrs
      )
    )

    Ash.Seed.seed!(UserSalary, %{
      member_id: employee.member.id,
      organization_id: organization_id,
      hourly_rate: Decimal.new("100"),
      starts_at: ~U[2025-12-01 00:00:00Z]
    })
  end

  defp blob_fixture!(organization_id) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/payroll/#{System.unique_integer([:positive])}.pdf",
      blob_checksum: "payroll-#{System.unique_integer([:positive])}",
      original_filename: "payroll.pdf",
      organization_id: organization_id
    })
  end

  defp processor_scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :document_blob_processor},
      tenant: organization_id
    }
  end
end
