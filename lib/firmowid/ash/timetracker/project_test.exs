defmodule Firmowid.Ash.Timetracker.ProjectTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Timetracker.Project, as: AshProject
  alias Firmowid.Ash.Timetracker.Session, as: AshSession

  setup do
    admin = admin_fixture()
    org_id = admin.organization_id

    scope = %Firmowid.Ash.Scope{
      current_user: admin,
      current_tenant: org_id
    }

    %{user: admin, org_id: org_id, scope: scope}
  end

  describe "create/2" do
    test "creates a project", %{scope: scope} do
      {:ok, project} = AshProject.create(%{name: "Test Project"}, scope: scope)

      assert project.name == "Test Project"
      assert is_nil(project.archived_at)
    end
  end

  describe "archive + unarchive" do
    test "archives and unarchives a project", %{scope: scope} do
      project = project_fixture()

      {:ok, archived} = AshProject.archive(project, scope: scope)
      assert archived.archived_at

      {:ok, restored} = AshProject.unarchive(archived, scope: scope)
      assert is_nil(restored.archived_at)
    end
  end

  describe "set_users/3" do
    test "assigns users to a project", %{user: user, org_id: org_id, scope: scope} do
      project = project_fixture(%{organization_id: org_id})
      user2 = user_in_org_fixture(org_id)

      {:ok, _} =
        AshProject.set_users([user.id, user2.id], %{project_id: project.id}, scope: scope)

      {:ok, users} = AshProject.project_users_with_removed(project.id, scope: scope)

      active_ids =
        users
        |> Enum.reject(& &1.removed_from_project)
        |> Enum.map(& &1.user.id)
        |> Enum.sort()

      assert active_ids == Enum.sort([user.id, user2.id])
    end
  end

  describe "all-time project totals" do
    defp insert_salary!(user_id, org_id, hourly_rate, updated_at, deleted_at) do
      Repo.insert!(
        %UserSalary{
          id: Ash.UUIDv7.generate(),
          user_id: user_id,
          organization_id: org_id,
          hourly_rate: Decimal.new(hourly_rate),
          deleted_at: deleted_at,
          inserted_at: updated_at,
          updated_at: updated_at
        },
        skip_organization_id: true
      )
    end

    test "total_time_worked sums durations across all months", %{
      user: user,
      org_id: org_id,
      scope: scope
    } do
      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user.id, project.id)

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-10 10:00:00Z],
        end_datetime: ~U[2025-01-10 11:00:00Z]
      })

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-05 10:00:00Z],
        end_datetime: ~U[2025-02-05 12:00:00Z]
      })

      {:ok, total} = AshSession.total_time_worked(%{project_id: project.id}, scope: scope)
      assert total == 3 * 3600
    end

    test "project_total_cost_all_time sums month-by-month cost using salary changes", %{
      user: user,
      org_id: org_id,
      scope: scope
    } do
      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user.id, project.id)

      insert_salary!(user.id, org_id, "50.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user.id, org_id, "100.00", ~U[2025-02-16 00:00:00Z], nil)

      # January: 1.5h -> ceil to 2h, rate 50 => 100
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-20 10:00:00Z],
        end_datetime: ~U[2025-01-20 11:30:00Z]
      })

      # February: 1h, rate 100 => 100
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-20 10:00:00Z],
        end_datetime: ~U[2025-02-20 11:00:00Z]
      })

      {:ok, total_cost} = AshProject.project_total_cost_all_time(project.id, scope: scope)
      assert Decimal.equal?(total_cost, Decimal.new("200"))
    end

    test "project_users_with_cost_all_time aggregates per-user data", %{
      user: user,
      org_id: org_id,
      scope: scope
    } do
      user2 = user_in_org_fixture(org_id)
      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user.id, project.id)
      user_project_fixture(user2.id, project.id)

      insert_salary!(user.id, org_id, "50.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user.id, org_id, "100.00", ~U[2025-02-16 00:00:00Z], nil)

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-20 10:00:00Z],
        end_datetime: ~U[2025-01-20 11:30:00Z]
      })

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-20 10:00:00Z],
        end_datetime: ~U[2025-02-20 11:00:00Z]
      })

      session_fixture(%{
        user_id: user2.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-10 10:00:00Z],
        end_datetime: ~U[2025-01-10 12:00:00Z]
      })

      {:ok, users_list} =
        AshProject.project_users_with_cost_all_time(project.id, scope: scope)

      users = Map.new(users_list, fn u -> {u.id, u} end)

      assert users[user.id].time_worked == 5400 + 3600
      assert Decimal.equal?(users[user.id].cost, Decimal.new("200"))
      assert users[user.id].expanded == false

      assert users[user2.id].time_worked == 7200
      # user2 has no salary, so cost is nil
      assert users[user2.id].cost == nil
      assert users[user2.id].expanded == false
    end

    test "handles multiple employees with salary changes", %{
      user: user,
      org_id: org_id,
      scope: scope
    } do
      user2 = user_in_org_fixture(org_id)
      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user.id, project.id)
      user_project_fixture(user2.id, project.id)

      insert_salary!(user.id, org_id, "50.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user.id, org_id, "100.00", ~U[2025-02-16 00:00:00Z], nil)
      insert_salary!(user2.id, org_id, "80.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user2.id, org_id, "40.00", ~U[2025-02-16 00:00:00Z], nil)

      # user1 Jan: 0.5h -> ceil 1h @ 50 => 50
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-10 10:00:00Z],
        end_datetime: ~U[2025-01-10 10:30:00Z]
      })

      # user2 Jan: 1.2h -> ceil 2h @ 80 => 160
      session_fixture(%{
        user_id: user2.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-10 11:00:00Z],
        end_datetime: ~U[2025-01-10 12:12:00Z]
      })

      # user1 Feb: 2.1h -> ceil 3h @ 100 => 300
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-10 10:00:00Z],
        end_datetime: ~U[2025-02-10 12:06:00Z]
      })

      # user2 Feb: 0.1h -> ceil 1h @ 40 => 40
      session_fixture(%{
        user_id: user2.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-10 13:00:00Z],
        end_datetime: ~U[2025-02-10 13:06:00Z]
      })

      u1_jan_seconds = 30 * 60
      u2_jan_seconds = 72 * 60
      u1_feb_seconds = (2 * 60 + 6) * 60
      u2_feb_seconds = 6 * 60
      total_seconds = u1_jan_seconds + u2_jan_seconds + u1_feb_seconds + u2_feb_seconds

      {:ok, total_time} =
        AshSession.total_time_worked(%{project_id: project.id}, scope: scope)

      assert total_time == total_seconds

      {:ok, total_cost} =
        AshProject.project_total_cost_all_time(project.id, scope: scope)

      # Jan: 50 + 160 = 210, Feb: 300 + 40 = 340, Total: 550
      assert Decimal.equal?(total_cost, Decimal.new("550"))

      {:ok, users_list} =
        AshProject.project_users_with_cost_all_time(project.id, scope: scope)

      users = Map.new(users_list, fn u -> {u.id, u} end)

      assert users[user.id].time_worked == u1_jan_seconds + u1_feb_seconds
      assert Decimal.equal?(users[user.id].cost, Decimal.new("350"))

      assert users[user2.id].time_worked == u2_jan_seconds + u2_feb_seconds
      assert Decimal.equal?(users[user2.id].cost, Decimal.new("200"))
    end
  end

  describe "month_summary_by_project" do
    test "returns users with time worked", %{user: user, org_id: org_id, scope: scope} do
      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user.id, project.id)

      session_fixture(%{
        project_id: project.id,
        user_id: user.id,
        start_datetime: ~U[2025-01-01 00:00:00Z],
        end_datetime: ~U[2025-01-01 02:00:00Z]
      })

      {:ok, summary} =
        AshProject.project_month_users_with_cost(
          project.id,
          ~D[2025-01-01],
          scope: scope
        )

      assert length(summary) == 1
      user_summary = hd(summary)
      assert user_summary.id == user.id
      assert user_summary.time_worked == 7200
    end

    test "returns empty list when no users in project", %{org_id: org_id, scope: scope} do
      project = project_fixture(%{organization_id: org_id})

      {:ok, summary} =
        AshProject.project_month_users_with_cost(
          project.id,
          ~D[2025-01-01],
          scope: scope
        )

      assert summary == []
    end
  end
end
