# credo:disable-for-this-file ExDNA.Credo
# Test setup duplicates another domain test by design (tenant-scoped fixture
# bootstrap); extracting shared helpers would cross domain boundaries and be
# larger than a small refactor.
defmodule Firmowid.Ash.Payroll.UserSalaryTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary

  setup do
    admin = admin_fixture()
    org_id = admin.organization_id

    scope = %Firmowid.Ash.Scope{
      actor: admin,
      tenant: org_id
    }

    %{user: admin, org_id: org_id, scope: scope}
  end

  describe "create_with_retire/2" do
    test "creates a salary record", %{user: user, scope: scope} do
      {:ok, salary} =
        AshUserSalary.create_with_retire(
          %{user_id: user.id, hourly_rate: Decimal.new("100.00")},
          scope: scope
        )

      assert Decimal.equal?(salary.hourly_rate, Decimal.new("100.00"))
      assert salary.user_id == user.id
      assert is_nil(salary.deleted_at)
    end

    test "retires existing salary when creating a new one", %{user: user, scope: scope} do
      {:ok, salary1} =
        AshUserSalary.create_with_retire(
          %{user_id: user.id, hourly_rate: Decimal.new("50.00")},
          scope: scope
        )

      {:ok, salary2} =
        AshUserSalary.create_with_retire(
          %{user_id: user.id, hourly_rate: Decimal.new("100.00")},
          scope: scope
        )

      # salary1 should now be retired
      retired = Repo.get(AshUserSalary, salary1.id)
      assert retired.deleted_at

      # salary2 should be active
      assert is_nil(salary2.deleted_at)
      assert Decimal.equal?(salary2.hourly_rate, Decimal.new("100.00"))
    end
  end

  describe "get_latest/2" do
    test "returns active salary for a user", %{user: user, scope: scope} do
      {:ok, _} =
        AshUserSalary.create_with_retire(
          %{user_id: user.id, hourly_rate: Decimal.new("75.00")},
          scope: scope
        )

      {:ok, latest} = AshUserSalary.get_latest(user.id, scope: scope)
      assert Decimal.equal?(latest.hourly_rate, Decimal.new("75.00"))
    end

    test "returns the newest active salary after updates", %{user: user, scope: scope} do
      {:ok, _} =
        AshUserSalary.create_with_retire(
          %{user_id: user.id, hourly_rate: Decimal.new("50.00")},
          scope: scope
        )

      {:ok, _} =
        AshUserSalary.create_with_retire(
          %{user_id: user.id, hourly_rate: Decimal.new("80.00")},
          scope: scope
        )

      {:ok, latest} = AshUserSalary.get_latest(user.id, scope: scope)
      assert Decimal.equal?(latest.hourly_rate, Decimal.new("80.00"))
    end
  end

  describe "as_of/2" do
    test "returns salary active at a given date", %{user: user, org_id: org_id, scope: scope} do
      # Insert salary directly with specific timestamps for deterministic test
      Repo.insert!(
        %AshUserSalary{
          id: Ash.UUIDv7.generate(),
          user_id: user.id,
          organization_id: org_id,
          hourly_rate: Decimal.new("60.00"),
          deleted_at: ~D[2025-02-15],
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
          inserted_at: ~U[2025-02-16 00:00:00Z],
          updated_at: ~U[2025-02-16 00:00:00Z]
        },
        skip_organization_id: true
      )

      # January: salary was 60
      {:ok, [jan_salary]} =
        AshUserSalary.as_of(~D[2025-01-15], %{user_id: user.id}, scope: scope)

      assert Decimal.equal?(jan_salary.hourly_rate, Decimal.new("60.00"))

      # March: salary is 90
      {:ok, [mar_salary]} =
        AshUserSalary.as_of(~D[2025-03-15], %{user_id: user.id}, scope: scope)

      assert Decimal.equal?(mar_salary.hourly_rate, Decimal.new("90.00"))
    end
  end
end
