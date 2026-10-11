defmodule Firmowid.Ash.Payroll.SalaryMatchingTest do
  @moduledoc "Critical amount boundaries, assignment uniqueness and payroll privacy regressions."

  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Payroll.SalaryMatching
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker.Project
  alias Firmowid.Ash.Timetracker.Session

  test "inclusive 300 PLN floor and 20 percent windows" do
    for {expected, minimum, maximum} <- [{300, 0, 600}, {1000, 700, 1300}, {5000, 4000, 6000}] do
      assert SalaryMatching.within_tolerance?(Decimal.new(minimum), Decimal.new(expected))
      assert SalaryMatching.within_tolerance?(Decimal.new(maximum), Decimal.new(expected))
      refute SalaryMatching.within_tolerance?(Decimal.new(minimum - 1), Decimal.new(expected))
      refute SalaryMatching.within_tolerance?(Decimal.new(maximum + 1), Decimal.new(expected))
    end
  end

  test "confirmation is persistent, unique per employee/month and excluded from invoice candidates" do
    {admin, scope, transaction} = salary_fixture()
    assert [%{user_id: user_id, month: month}] = SalaryMatching.suggestions(transaction, scope)

    assert {:ok, assigned} =
             Finances.connect_transaction_salary(
               transaction,
               %{salary_user_id: user_id, salary_month: month},
               scope: scope
             )

    assert assigned.salary_user_id == user_id
    assert Finances.list_transactions!(%{reconciliation: :pending}, scope: scope) == []

    assert [matched] =
             Finances.list_transactions!(%{reconciliation: :matched},
               load: [:has_salary?],
               scope: scope
             )

    assert matched.has_salary?

    matcher_scope =
      Scope.new!(
        %SystemActor{org_id: admin.organization_id, role: :invoice_matcher},
        admin.organization_id
      )

    assert Finances.list_transactions!(%{reconciliation: :pending}, scope: matcher_scope) == []
    assert [_] = Finances.list_transactions!(%{salary_assigned: true}, scope: matcher_scope)

    second = seed_transaction(admin, transaction.bank_account_id)
    assert SalaryMatching.suggestions(load_transaction(second.id, scope), scope) == []

    assert {:error, _} =
             Finances.connect_transaction_salary(
               second,
               %{salary_user_id: user_id, salary_month: month},
               scope: scope
             )

    assert {:ok, _} = Finances.disconnect_transaction_salary(assigned, %{}, scope: scope)
    assert [_] = SalaryMatching.suggestions(load_transaction(transaction.id, scope), scope)
  end

  test "invoice users cannot read payroll identity or mutate a salary assignment" do
    {admin, scope, transaction} = salary_fixture()
    assert [candidate] = SalaryMatching.suggestions(transaction, scope)

    assert {:ok, assigned} =
             Finances.connect_transaction_salary(
               transaction,
               %{salary_user_id: candidate.user_id, salary_month: candidate.month},
               scope: scope
             )

    accountant = user_in_org_fixture(admin.organization_id, %{role: :accountant})
    accountant_scope = Scope.new!(accountant, admin.organization_id)

    hidden =
      Finances.get_transaction!(assigned.id,
        load: [:has_salary?, :salary_user],
        scope: accountant_scope
      )

    assert hidden.has_salary?
    assert %Ash.ForbiddenField{} = hidden.salary_user_id
    assert %Ash.ForbiddenField{} = hidden.salary_month
    assert is_nil(hidden.salary_user)
    assert Finances.list_transactions!(%{reconciliation: :pending}, scope: accountant_scope) == []
    assert SalaryMatching.suggestions(transaction, accountant_scope) == []

    assert {:error, _} =
             Finances.disconnect_transaction_salary(hidden, %{}, scope: accountant_scope)

    other_admin = admin_fixture()

    assert {:error, _} =
             Finances.get_transaction(assigned.id,
               scope: Scope.new!(other_admin, other_admin.organization_id)
             )
  end

  defp salary_fixture do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.organization_id)
    account = bank_account_fixture!(admin)

    project =
      Ash.Seed.seed!(Project, %{name: "Salary matching", organization_id: admin.organization_id},
        tenant: admin.organization_id
      )

    Ash.Seed.seed!(
      UserSalary,
      %{
        user_id: admin.id,
        hourly_rate: Decimal.new(100),
        starts_at: ~U[2026-09-01 00:00:00Z],
        organization_id: admin.organization_id
      },
      tenant: admin.organization_id
    )

    Ash.Seed.seed!(
      Session,
      %{
        user_id: admin.id,
        project_id: project.id,
        title: "Monthly work",
        start_datetime: ~U[2026-09-10 09:00:00Z],
        end_datetime: ~U[2026-09-10 12:00:00Z],
        organization_id: admin.organization_id
      },
      tenant: admin.organization_id
    )

    transaction = seed_transaction(admin, account.id)
    {admin, scope, load_transaction(transaction.id, scope)}
  end

  defp seed_transaction(admin, account_id) do
    Ash.Seed.seed!(
      Transaction,
      %{
        bank_account_id: account_id,
        organization_id: admin.organization_id,
        amount: Money.new!(:PLN, -600),
        booking_date: ~D[2026-10-10],
        value_date: ~D[2026-10-10],
        internal_transaction_id: Ash.UUID.generate()
      },
      tenant: admin.organization_id
    )
  end

  defp load_transaction(id, scope),
    do:
      Finances.get_transaction!(id,
        load: [:bank_account, :direction, :has_salary?, :cost_invoices, :sales_invoices],
        scope: scope
      )
end
