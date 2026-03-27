defmodule Firmowid.Ash.Policies.TimetrackerPayrollPoliciesTest do
  @moduledoc """
  Tests that Ash policies on Timetracker and Payroll resources correctly
  restrict access based on the actor's role and ownership.

  These tests exercise the authorization boundary at the resource layer,
  ensuring defense-in-depth regardless of what the caller (LiveView,
  controller, context module) does.
  """
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.ProjectUser, as: AshProjectUser

  # ── Helpers ──────────────────────────────────────────────────────────

  defp admin_scope(admin) do
    %Scope{current_user: admin, current_tenant: admin.organization_id}
  end

  defp employee_scope(employee) do
    %Scope{current_user: employee, current_tenant: employee.organization_id}
  end

  defp setup_org(_context) do
    admin = admin_fixture()
    org_id = admin.organization_id

    employee_a = user_in_org_fixture(org_id, %{role: :employee})
    employee_b = user_in_org_fixture(org_id, %{role: :employee})

    %{admin: admin, employee_a: employee_a, employee_b: employee_b, org_id: org_id}
  end

  defp insert_hours_record!(user, month, year) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    id = Ash.UUIDv7.generate()

    {:ok, id_bin} = Ecto.UUID.dump(id)
    {:ok, uid_bin} = Ecto.UUID.dump(user.id)
    {:ok, oid_bin} = Ecto.UUID.dump(user.organization_id)

    Repo.query!(
      """
      INSERT INTO hours_records (id, month, year, number_of_hours, user_id, organization_id, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      """,
      [id_bin, month, year, 160, uid_bin, oid_bin, now, now]
    )

    %{id: id, user_id: user.id, month: month, year: year}
  end

  # ── UserSalary policies ─────────────────────────────────────────────

  describe "UserSalary policies" do
    setup :setup_org

    setup %{employee_a: employee_a, employee_b: employee_b} do
      salary_a = user_salary_fixture(%{user_id: employee_a.id})
      salary_b = user_salary_fixture(%{user_id: employee_b.id})

      %{salary_a: salary_a, salary_b: salary_b}
    end

    test "admin can read all salaries", %{admin: admin} do
      scope = admin_scope(admin)

      assert {:ok, salaries} =
               AshUserSalary
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)

      assert length(salaries) >= 2
    end

    test "employee cannot read any salary", %{employee_a: employee_a} do
      scope = employee_scope(employee_a)

      assert {:ok, []} =
               AshUserSalary
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)
    end

    test "employee cannot read their own salary via get_latest", %{
      employee_a: employee_a
    } do
      scope = employee_scope(employee_a)

      # get? action returns NotFound (wrapped in Invalid) when policy filters
      # out the record — the employee has a salary but cannot see it.
      assert {:error, %Invalid{}} =
               AshUserSalary.get_latest(employee_a.id, scope: scope)
    end
  end

  # ── HoursRecord policies ────────────────────────────────────────────

  describe "HoursRecord policies" do
    setup :setup_org

    setup %{employee_a: employee_a, employee_b: employee_b} do
      project = project_fixture()
      user_project_fixture(employee_a.id, project.id)
      user_project_fixture(employee_b.id, project.id)

      now = Date.utc_today()
      hr_a = insert_hours_record!(employee_a, now.month, now.year)
      hr_b = insert_hours_record!(employee_b, now.month, now.year)

      %{hr_a: hr_a, hr_b: hr_b}
    end

    test "admin can read all hours records", %{admin: admin} do
      scope = admin_scope(admin)

      assert {:ok, records} =
               AshHoursRecord
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)

      assert length(records) >= 2
    end

    test "employee can read only their own hours record", %{
      employee_a: employee_a,
      hr_a: hr_a
    } do
      scope = employee_scope(employee_a)

      assert {:ok, records} =
               AshHoursRecord
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)

      assert length(records) == 1
      assert hd(records).id == hr_a.id
    end

    test "employee cannot read another employee's hours record via by_month", %{
      employee_a: employee_a,
      employee_b: employee_b
    } do
      scope = employee_scope(employee_a)
      now = Date.utc_today()

      # by_month is a get? action — returns NotFound when policy filters out the record
      assert {:error, %Invalid{}} =
               AshHoursRecord.by_month(employee_b.id, now.month, now.year, scope: scope)
    end

    test "employee cannot call month_hours_records generic action", %{
      employee_a: employee_a
    } do
      scope = employee_scope(employee_a)
      now = Date.utc_today()

      assert {:error, %Forbidden{}} =
               AshHoursRecord.month_hours_records(now.month, now.year, scope: scope)
    end

    test "admin can call month_hours_records generic action", %{admin: admin} do
      scope = admin_scope(admin)
      now = Date.utc_today()

      assert {:ok, _results} =
               AshHoursRecord.month_hours_records(now.month, now.year, scope: scope)
    end
  end

  # ── Project policies ────────────────────────────────────────────────

  describe "Project policies" do
    setup :setup_org

    setup %{employee_a: employee_a} do
      project_assigned = project_fixture(%{name: "Assigned Project"})
      project_unassigned = project_fixture(%{name: "Unassigned Project"})

      user_project_fixture(employee_a.id, project_assigned.id)

      %{project_assigned: project_assigned, project_unassigned: project_unassigned}
    end

    test "admin can read all projects", %{admin: admin} do
      scope = admin_scope(admin)

      assert {:ok, projects} =
               AshProject
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)

      assert length(projects) >= 2
    end

    test "employee can read only assigned projects", %{
      employee_a: employee_a,
      project_assigned: project_assigned
    } do
      scope = employee_scope(employee_a)

      assert {:ok, projects} =
               AshProject
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)

      project_ids = Enum.map(projects, & &1.id)
      assert project_assigned.id in project_ids
      assert length(project_ids) == 1
    end

    test "employee cannot read unassigned project via get", %{
      employee_a: employee_a,
      project_unassigned: project_unassigned
    } do
      scope = employee_scope(employee_a)

      # get? action wraps NotFound in Invalid
      assert {:error, %Invalid{}} =
               AshProject.get(project_unassigned.id, scope: scope)
    end

    test "employee cannot call generic actions (admin-only)", %{
      employee_a: employee_a
    } do
      scope = employee_scope(employee_a)

      assert {:error, %Forbidden{}} =
               AshProject.active(Date.utc_today(), scope: scope)
    end
  end

  # ── ProjectUser policies ────────────────────────────────────────────

  describe "ProjectUser policies" do
    setup :setup_org

    setup %{employee_a: employee_a, employee_b: employee_b} do
      project = project_fixture()
      pu_a = user_project_fixture(employee_a.id, project.id)
      pu_b = user_project_fixture(employee_b.id, project.id)

      %{project: project, pu_a: pu_a, pu_b: pu_b}
    end

    test "admin can read all project_users", %{admin: admin} do
      scope = admin_scope(admin)

      assert {:ok, pus} =
               AshProjectUser
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)

      assert length(pus) >= 2
    end

    test "employee can read only their own project assignments", %{
      employee_a: employee_a,
      pu_a: pu_a
    } do
      scope = employee_scope(employee_a)

      assert {:ok, pus} =
               AshProjectUser
               |> Ash.Query.for_read(:read, %{}, scope: scope)
               |> Ash.read(scope: scope)

      assert length(pus) == 1
      assert hd(pus).id == pu_a.id
    end
  end
end
