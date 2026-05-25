# credo:disable-for-this-file ExDNA.Credo
# Test setup duplicates another domain test by design (tenant-scoped fixture
# bootstrap); extracting shared helpers would cross domain boundaries and be
# larger than a small refactor.
defmodule Firmowid.Ash.Payroll.UserSalaryTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary

  setup do
    admin = admin_fixture()
    user = user_in_org_fixture(admin.organization_id)
    org_id = admin.organization_id

    scope = %Firmowid.Ash.Scope{
      actor: admin,
      tenant: org_id
    }

    %{user: admin, other_user: user, org_id: org_id, scope: scope}
  end

  describe "create/2" do
    test "creates a salary record", %{user: user, scope: scope} do
      {:ok, salary} =
        Payroll.create_salary(
          %{user_id: user.id, hourly_rate: Decimal.new("100.00")},
          scope: scope
        )

      assert Decimal.equal?(salary.hourly_rate, Decimal.new("100.00"))
      assert salary.user_id == user.id
      assert DateTime.compare(salary.starts_at, DateTime.utc_now()) in [:lt, :eq]
    end
  end

  describe "bulk_create/2" do
    test "creates multiple salary records", %{user: user, other_user: other_user, scope: scope} do
      entries = [
        %{user_id: user.id, hourly_rate: Decimal.new("80.00")},
        %{user_id: other_user.id, hourly_rate: Decimal.new("120.00")}
      ]

      {:ok, salaries} = Payroll.bulk_create_salaries(entries, scope: scope)

      assert length(salaries) == 2
      assert Enum.any?(salaries, fn s -> Decimal.equal?(s.hourly_rate, Decimal.new("80.00")) end)
      assert Enum.any?(salaries, fn s -> Decimal.equal?(s.hourly_rate, Decimal.new("120.00")) end)
    end
  end

  describe "list_salaries/2" do
    setup %{
      user: user,
      other_user: other_user,
      org_id: org_id
    } do
      Repo.insert!(
        %AshUserSalary{
          id: Ash.UUIDv7.generate(),
          user_id: user.id,
          organization_id: org_id,
          hourly_rate: Decimal.new("60.00"),
          starts_at: ~U[2024-12-10 00:00:00Z],
          inserted_at: ~U[2025-01-01 00:00:00Z],
          updated_at: ~U[2025-01-01 00:00:00Z]
        },
        skip_organization_id: true
      )

      Repo.insert!(
        %AshUserSalary{
          id: Ash.UUIDv7.generate(),
          user_id: user.id,
          organization_id: org_id,
          hourly_rate: Decimal.new("90.00"),
          starts_at: ~U[2025-02-15 00:00:00Z],
          inserted_at: ~U[2025-02-16 00:00:00Z],
          updated_at: ~U[2025-02-16 00:00:00Z]
        },
        skip_organization_id: true
      )

      Repo.insert!(
        %AshUserSalary{
          id: Ash.UUIDv7.generate(),
          user_id: other_user.id,
          organization_id: org_id,
          hourly_rate: Decimal.new("35.00"),
          starts_at: ~U[2024-12-30 00:00:00Z],
          inserted_at: ~U[2025-02-16 00:00:00Z],
          updated_at: ~U[2025-02-16 00:00:00Z]
        },
        skip_organization_id: true
      )

      :ok
    end

    test "returns salary active at a given date", %{
      user: user,
      scope: scope
    } do
      # January: salary was 60
      {:ok, [jan_salary]} =
        Payroll.list_salaries(%{user_id: user.id, active_at: ~D[2025-01-15]},
          scope: scope
        )

      assert Decimal.equal?(jan_salary.hourly_rate, Decimal.new("60.00"))

      # March: salary is 90
      {:ok, [mar_salary]} =
        Payroll.list_salaries(%{user_id: user.id, active_at: ~D[2025-03-15]},
          scope: scope
        )

      assert Decimal.equal?(mar_salary.hourly_rate, Decimal.new("90.00"))

      # Today: salary is 90 - the latest salary record with no end date is active
      {:ok, [mar_salary]} =
        Payroll.list_salaries(%{user_id: user.id, active_at: Date.utc_today()},
          scope: scope
        )

      assert Decimal.equal?(mar_salary.hourly_rate, Decimal.new("90.00"))
    end

    test "returns salary active for multiple users", %{
      user: user,
      other_user: other_user,
      scope: scope
    } do
      # Today multiple users: both salaries should be returned for the user, and the other user's salary should also be returned
      {:ok, salaries} =
        Payroll.list_salaries(%{active_at: Date.utc_today()},
          scope: scope
        )

      assert length(salaries) == 2

      assert Enum.any?(
               salaries,
               &(&1.user_id == user.id and Decimal.equal?(&1.hourly_rate, Decimal.new("90.00")))
             )

      assert Enum.any?(
               salaries,
               &(&1.user_id == other_user.id and
                   Decimal.equal?(&1.hourly_rate, Decimal.new("35.00")))
             )
    end

    test "returns full salary history for given user", %{
      user: user,
      scope: scope
    } do
      # Full history: both records returned
      {:ok, salaries} =
        Payroll.list_salaries(%{user_id: user.id}, scope: scope)

      assert length(salaries) == 2
      assert Enum.all?(salaries, fn s -> s.user_id == user.id end)
      assert Enum.any?(salaries, fn s -> Decimal.equal?(s.hourly_rate, Decimal.new("60.00")) end)
      assert Enum.any?(salaries, fn s -> Decimal.equal?(s.hourly_rate, Decimal.new("90.00")) end)
    end

    test "returns full salary history for all users", %{
      user: user,
      other_user: other_user,
      scope: scope
    } do
      # Full history for all users: all records returned
      {:ok, salaries} =
        Payroll.list_salaries(%{}, scope: scope)

      assert length(salaries) == 3

      assert Enum.any?(
               salaries,
               &(&1.user_id == user.id and Decimal.equal?(&1.hourly_rate, Decimal.new("60.00")))
             )

      assert Enum.any?(
               salaries,
               &(&1.user_id == user.id and Decimal.equal?(&1.hourly_rate, Decimal.new("90.00")))
             )

      assert Enum.any?(
               salaries,
               &(&1.user_id == other_user.id and
                   Decimal.equal?(&1.hourly_rate, Decimal.new("35.00")))
             )
    end
  end
end
