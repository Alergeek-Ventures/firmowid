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

  alias Ash.Error.Invalid
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.ProjectUser, as: AshProjectUser

  # ── Helpers ──────────────────────────────────────────────────────────

  defp admin_scope(admin) do
    %Scope{actor: admin, tenant: admin.organization_id}
  end

  defp employee_scope(employee) do
    %Scope{actor: employee, tenant: employee.organization_id}
  end

  defp setup_org(_context) do
    admin = admin_fixture()
    org_id = admin.organization_id

    employee_a = user_in_org_fixture(org_id, %{role: :employee})
    employee_b = user_in_org_fixture(org_id, %{role: :employee})

    %{admin: admin, employee_a: employee_a, employee_b: employee_b, org_id: org_id}
  end

  defp insert_hours_record!(user, month, year) do
    now = NaiveDateTime.utc_now(:second)
    id = Ash.UUIDv7.generate()

    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/path/hr_#{System.unique_integer([:positive])}.pdf",
        blob_checksum: "hr-policy-#{System.unique_integer([:positive])}",
        original_filename: "hours_record.pdf",
        organization_id: user.organization_id
      })

    {:ok, id_bin} = Ecto.UUID.dump(id)
    {:ok, uid_bin} = Ecto.UUID.dump(user.id)
    {:ok, oid_bin} = Ecto.UUID.dump(user.organization_id)
    {:ok, bid_bin} = Ecto.UUID.dump(blob.id)

    Repo.query!(
      """
      INSERT INTO hours_records (id, month, year, number_of_hours, blob_id, user_id, organization_id, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      """,
      [id_bin, month, year, 160, bid_bin, uid_bin, oid_bin, now, now]
    )

    %{id: id, user_id: user.id, month: month, year: year}
  end

  # ── UserSalary policies ─────────────────────────────────────────────

  describe "UserSalary policies" do
    setup :setup_org

    setup %{employee_a: employee_a, employee_b: employee_b, org_id: org_id} do
      salary_a = user_salary_fixture(%{user_id: employee_a.id, organization_id: org_id})
      salary_b = user_salary_fixture(%{user_id: employee_b.id, organization_id: org_id})

      %{salary_a: salary_a, salary_b: salary_b}
    end

    test "admin can read all salaries", %{admin: admin} do
      scope = admin_scope(admin)

      assert {:ok, salaries} = Payroll.list_salaries(%{}, scope: scope)

      assert length(salaries) >= 2
    end

    test "employee cannot read their own salary via list_salaries", %{
      employee_a: employee_a
    } do
      scope = employee_scope(employee_a)

      assert {:error, _} =
               Payroll.list_salaries(%{user_id: employee_a.id}, scope: scope)
    end
  end

  # ── HoursRecord policies ────────────────────────────────────────────

  describe "HoursRecord policies" do
    setup :setup_org

    setup %{employee_a: employee_a, employee_b: employee_b, org_id: org_id} do
      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(employee_a.id, project.id, org_id)
      user_project_fixture(employee_b.id, project.id, org_id)

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
  end

  # ── Project policies ────────────────────────────────────────────────

  describe "Project policies" do
    setup :setup_org

    setup %{employee_a: employee_a, org_id: org_id} do
      project_assigned = project_fixture(%{name: "Assigned Project", organization_id: org_id})
      project_unassigned = project_fixture(%{name: "Unassigned Project", organization_id: org_id})

      user_project_fixture(employee_a.id, project_assigned.id, org_id)

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
  end

  # ── ProjectUser policies ────────────────────────────────────────────

  describe "ProjectUser policies" do
    setup :setup_org

    setup %{employee_a: employee_a, employee_b: employee_b, org_id: org_id} do
      project = project_fixture(%{organization_id: org_id})
      pu_a = user_project_fixture(employee_a.id, project.id, org_id)
      pu_b = user_project_fixture(employee_b.id, project.id, org_id)

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
