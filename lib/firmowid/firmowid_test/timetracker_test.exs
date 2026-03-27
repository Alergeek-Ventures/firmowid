defmodule Firmowid.TimetrackerTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.UserSalary

  test "lists projects with users" do
    user = user_fixture()

    {:ok, _} =
      Timetracker.create_project(%{name: "test project", organization_id: user.organization_id})

    project_list = Timetracker.list_projects_with_users()

    [project] = project_list

    assert project.name == "test project"
    assert project.users == []

    {:ok, _} = Timetracker.add_user_to_project(user.id, project.id)

    user = Repo.preload(user, :projects)

    [users_project] = user.projects

    assert users_project.id == project.id
    assert users_project.name == "test project"

    project_list_updated = Timetracker.list_projects_with_users()

    [project_updated] = project_list_updated

    assert project_updated.name == "test project"
    assert length(project_updated.users) == 1
  end

  describe "all-time project totals" do
    defp insert_salary!(user_id, organization_id, hourly_rate, updated_at, deleted_at) do
      Repo.insert!(%UserSalary{
        user_id: user_id,
        organization_id: organization_id,
        hourly_rate: Decimal.new(hourly_rate),
        deleted_at: deleted_at,
        inserted_at: updated_at,
        updated_at: updated_at
      })
    end

    test "get_project_total_time_worked_all_time/1 sums durations across all months" do
      user = user_fixture()
      org_id = user.organization_id

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

      assert Timetracker.get_project_total_time_worked_all_time(project.id) == 3 * 60 * 60
    end

    test "get_project_total_cost_all_time/1 sums month-by-month cost using month-end hourly rate (salary changes)" do
      user = user_fixture()
      org_id = user.organization_id

      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user.id, project.id)

      insert_salary!(user.id, org_id, "50.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user.id, org_id, "100.00", ~U[2025-02-16 00:00:00Z], nil)

      # January: 1.5h -> ceil to 2h, rate 50
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-20 10:00:00Z],
        end_datetime: ~U[2025-01-20 11:30:00Z]
      })

      # February: 1h, rate 100
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-20 10:00:00Z],
        end_datetime: ~U[2025-02-20 11:00:00Z]
      })

      assert Decimal.equal?(Timetracker.get_project_total_cost_all_time(project.id), Decimal.new("200"))
    end

    test "get_project_users_with_cost_all_time/1 aggregates per-user time and monthly-rounded cost (salary changes + missing salary)" do
      user1 = user_fixture()
      org_id = user1.organization_id
      user2 = user_in_org_fixture(org_id)

      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user1.id, project.id)
      user_project_fixture(user2.id, project.id)

      insert_salary!(user1.id, org_id, "50.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user1.id, org_id, "100.00", ~U[2025-02-16 00:00:00Z], nil)

      session_fixture(%{
        user_id: user1.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-20 10:00:00Z],
        end_datetime: ~U[2025-01-20 11:30:00Z]
      })

      session_fixture(%{
        user_id: user1.id,
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

      users =
        project.id
        |> Timetracker.get_project_users_with_cost_all_time()
        |> Map.new(fn u -> {u.id, u} end)

      assert users[user1.id].time_worked == 5400 + 3600
      assert Decimal.equal?(users[user1.id].cost, Decimal.new("200"))
      assert users[user1.id].hourly_rate == nil
      assert users[user1.id].expanded == false

      assert users[user2.id].time_worked == 7200
      assert users[user2.id].cost == nil
      assert users[user2.id].expanded == false
    end

    test "all-time totals handle multiple employees with salary changes" do
      user1 = user_fixture()
      org_id = user1.organization_id
      user2 = user_in_org_fixture(org_id)

      project = project_fixture(%{organization_id: org_id})
      user_project_fixture(user1.id, project.id)
      user_project_fixture(user2.id, project.id)

      insert_salary!(user1.id, org_id, "50.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user1.id, org_id, "100.00", ~U[2025-02-16 00:00:00Z], nil)

      insert_salary!(user2.id, org_id, "80.00", ~U[2025-01-01 00:00:00Z], ~D[2025-02-15])
      insert_salary!(user2.id, org_id, "40.00", ~U[2025-02-16 00:00:00Z], nil)

      # January month-end rates (2025-01-31):
      # - user1: 50 PLN/h
      # - user2: 80 PLN/h
      #
      # February month-end rates (2025-02-28):
      # - user1: 100 PLN/h
      # - user2: 40 PLN/h

      # Session durations and their monthly cost contribution.
      # Note: cost rounds per-user time in a month up to full hours.

      # January
      u1_jan_seconds = 30 * 60
      # user1: 0.5h -> ceil(0.5)=1h @ 50 => 50
      u2_jan_seconds = 72 * 60
      # user2: 1.2h -> ceil(1.2)=2h @ 80 => 160

      session_fixture(%{
        user_id: user1.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-10 10:00:00Z],
        end_datetime: ~U[2025-01-10 10:30:00Z]
      })

      session_fixture(%{
        user_id: user2.id,
        project_id: project.id,
        start_datetime: ~U[2025-01-10 11:00:00Z],
        end_datetime: ~U[2025-01-10 12:12:00Z]
      })

      # February
      u1_feb_seconds = (2 * 60 + 6) * 60
      # user1: 2.1h -> ceil(2.1)=3h @ 100 => 300
      u2_feb_seconds = 6 * 60
      # user2: 0.1h -> ceil(0.1)=1h @ 40 => 40

      session_fixture(%{
        user_id: user1.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-10 10:00:00Z],
        end_datetime: ~U[2025-02-10 12:06:00Z]
      })

      session_fixture(%{
        user_id: user2.id,
        project_id: project.id,
        start_datetime: ~U[2025-02-10 13:00:00Z],
        end_datetime: ~U[2025-02-10 13:06:00Z]
      })

      total_seconds = u1_jan_seconds + u2_jan_seconds + u1_feb_seconds + u2_feb_seconds
      assert Timetracker.get_project_total_time_worked_all_time(project.id) == total_seconds

      expected_total_cost = Decimal.new("550")
      # January: 50 + 160 = 210
      # February: 300 + 40 = 340
      # Total: 550
      assert Decimal.equal?(Timetracker.get_project_total_cost_all_time(project.id), expected_total_cost)

      users =
        project.id
        |> Timetracker.get_project_users_with_cost_all_time()
        |> Map.new(fn u -> {u.id, u} end)

      assert users[user1.id].time_worked == u1_jan_seconds + u1_feb_seconds
      assert Decimal.equal?(users[user1.id].cost, Decimal.new("350"))

      assert users[user2.id].time_worked == u2_jan_seconds + u2_feb_seconds
      assert Decimal.equal?(users[user2.id].cost, Decimal.new("200"))
    end
  end

  test "get_total_time_worked" do
    user = user_fixture()

    project = project_fixture()
    user_project_fixture(user.id, project.id)

    assert Timetracker.get_total_time_worked(4, 2025) == 0

    session_fixture(%{
      user_id: user.id,
      project_id: project.id,
      start_datetime: ~U[2025-04-01 00:00:00Z],
      end_datetime: ~U[2025-04-01 01:00:00Z]
    })

    assert Timetracker.get_total_time_worked(4, 2025) == 60 * 60

    assert Timetracker.get_total_time_worked(5, 2025) == 0
    assert Timetracker.get_total_time_worked(3, 2025) == 0
  end

  describe "get_total_time_worked/2" do
    test "get_total_time_worked with multiple sessions" do
      user1 = user_fixture()
      user2 = user_fixture()

      project = project_fixture(%{organization_id: user1.organization_id})
      user_project_fixture(user1.id, project.id)
      user_project_fixture(user2.id, project.id)

      sessions = [
        %{
          user_id: user1.id,
          project_id: project.id,
          start_datetime: ~U[2025-04-01 00:00:00Z],
          end_datetime: ~U[2025-04-01 01:00:00Z]
        },
        %{
          user_id: user1.id,
          project_id: project.id,
          start_datetime: ~U[2025-04-01 01:00:00Z],
          end_datetime: ~U[2025-04-01 02:00:00Z]
        },
        %{
          user_id: user1.id,
          project_id: project.id,
          start_datetime: ~U[2025-04-01 02:00:00Z],
          end_datetime: ~U[2025-04-01 03:00:00Z]
        }
      ]

      duration =
        sessions
        |> Enum.map(&Session.put_duration/1)
        |> Enum.reduce(0, fn session, acc ->
          acc + session.duration
        end)

      Enum.each(sessions, &session_fixture(&1))
      assert Timetracker.get_total_time_worked(4, 2025) == duration
    end

    test "get_total_time_worked with multiple projects" do
      user = user_fixture()

      project1 = project_fixture()
      user_project_fixture(user.id, project1.id)

      project2 = project_fixture()
      user_project_fixture(user.id, project2.id)

      assert Timetracker.get_total_time_worked(4, 2025) == 0

      session_fixture(%{
        user_id: user.id,
        project_id: project1.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      assert Timetracker.get_total_time_worked(4, 2025) == 60 * 60

      session_fixture(%{
        user_id: user.id,
        project_id: project2.id,
        start_datetime: ~U[2025-04-01 01:00:00Z],
        end_datetime: ~U[2025-04-01 02:00:00Z]
      })

      assert Timetracker.get_total_time_worked(4, 2025) == 120 * 60
    end
  end

  test "get_months_with_sessions" do
    user = user_fixture()

    project = project_fixture()
    user_project_fixture(user.id, project.id)

    assert Timetracker.get_months_with_sessions() == []

    session_fixture(%{
      user_id: user.id,
      project_id: project.id,
      start_datetime: ~U[2025-04-01 00:00:00Z],
      end_datetime: ~U[2025-04-01 01:00:00Z]
    })

    assert Timetracker.get_months_with_sessions()
           |> Enum.map(&NaiveDateTime.truncate(&1, :second))
           |> Kernel.==([~N[2025-04-01 00:00:00]])

    session_fixture(%{
      user_id: user.id,
      project_id: project.id,
      start_datetime: ~U[2025-04-02 00:00:00Z],
      end_datetime: ~U[2025-04-02 01:00:00Z]
    })

    assert Timetracker.get_months_with_sessions()
           |> Enum.map(&NaiveDateTime.truncate(&1, :second))
           |> Kernel.==([
             ~N[2025-04-01 00:00:00]
           ])

    session_fixture(%{
      user_id: user.id,
      project_id: project.id,
      start_datetime: ~U[2025-05-01 00:00:00Z],
      end_datetime: ~U[2025-05-01 01:00:00Z]
    })

    assert Timetracker.get_months_with_sessions()
           |> Enum.map(&NaiveDateTime.truncate(&1, :second))
           |> Kernel.==([
             ~N[2025-04-01 00:00:00],
             ~N[2025-05-01 00:00:00]
           ])
  end

  test "get_most_demanding_project" do
    user = user_fixture()

    project1 = project_fixture()
    user_project_fixture(user.id, project1.id)

    project2 = project_fixture()
    user_project_fixture(user.id, project2.id)

    assert Timetracker.get_most_demanding_project(4, 2025) == nil

    session_fixture(%{
      user_id: user.id,
      project_id: project1.id,
      start_datetime: ~U[2025-04-01 00:00:00Z],
      end_datetime: ~U[2025-04-01 01:00:00Z]
    })

    %{project: project, time_worked: time_worked} =
      Timetracker.get_most_demanding_project(4, 2025)

    assert project.id == project1.id
    assert time_worked == 60 * 60

    session_fixture(%{
      user_id: user.id,
      project_id: project1.id,
      start_datetime: ~U[2025-05-01 01:00:00Z],
      end_datetime: ~U[2025-05-01 03:00:00Z]
    })

    session_fixture(%{
      user_id: user.id,
      project_id: project2.id,
      start_datetime: ~U[2025-04-01 03:00:00Z],
      end_datetime: ~U[2025-04-01 05:00:00Z]
    })

    %{project: project, time_worked: time_worked} =
      Timetracker.get_most_demanding_project(4, 2025)

    assert project.id == project2.id
    assert time_worked == 60 * 60 * 2
  end

  describe "get_month_summary_by_project/3" do
    test "returns project summary with users and their time worked" do
      user = user_fixture()
      project = project_fixture()
      user_project_fixture(user.id, project.id)

      session_fixture(%{
        project_id: project.id,
        user_id: user.id,
        start_datetime: ~U[2025-01-01 00:00:00Z],
        end_datetime: ~U[2025-01-01 02:00:00Z]
      })

      summary = Timetracker.get_month_summary_by_project(project.id, 1, 2025)
      assert length(summary) == 1

      user_summary = hd(summary)
      assert user_summary.user.id == user.id
      # 2 hours in seconds
      assert user_summary.time_worked == 7200
      assert user_summary.removed_from_project == false
    end

    test "returns empty list when no users in project" do
      # Creates organization
      user_fixture()
      project = project_fixture()
      assert Timetracker.get_month_summary_by_project(project.id, 1, 2025) == []
    end

    test "includes users with past sessions but removed from project" do
      user = user_fixture()
      project = project_fixture()
      user_project_fixture(user.id, project.id)

      session_fixture(%{
        project_id: project.id,
        user_id: user.id,
        start_datetime: ~U[2025-01-01 00:00:00Z],
        end_datetime: ~U[2025-01-01 01:00:00Z]
      })

      {1, _} = Timetracker.remove_user_from_project(user.id, project.id)

      summary = Timetracker.get_month_summary_by_project(project.id, 1, 2025)
      assert length(summary) == 1

      user_summary = hd(summary)
      assert user_summary.user.id == user.id
      # 1 hour in seconds
      assert user_summary.time_worked == 3600
      assert user_summary.removed_from_project == true
    end
  end

  test "prevents overlapping sessions for the same user" do
    user = user_fixture()
    project = project_fixture()
    user_project_fixture(user.id, project.id)

    # First session
    session_fixture(%{
      user_id: user.id,
      project_id: project.id,
      start_datetime: ~U[2025-04-01 00:00:00Z],
      end_datetime: ~U[2025-04-01 01:00:00Z]
    })

    # Overlapping session using context (should return {:error, :overlap})
    result =
      Timetracker.start_session(%{
        "user_id" => user.id,
        "project_id" => project.id,
        "title" => "Overlap",
        "start_datetime" => ~U[2025-04-01 00:30:00Z],
        "end_datetime" => ~U[2025-04-01 01:30:00Z]
      })

    assert result == {:error, :overlap}
  end

  test "prevents overlapping ongoing sessions (end_datetime is nil)" do
    user = user_fixture()
    project = project_fixture()
    user_project_fixture(user.id, project.id)

    # Ongoing session
    session_fixture(%{
      user_id: user.id,
      project_id: project.id,
      start_datetime: ~U[2025-04-01 00:00:00Z],
      end_datetime: nil
    })

    # Another ongoing session, overlapping in time, should NOT be allowed (should return {:error, :overlap})
    result =
      Timetracker.start_session(%{
        "user_id" => user.id,
        "project_id" => project.id,
        "title" => "Overlap",
        "start_datetime" => ~U[2025-04-01 00:30:00Z],
        "end_datetime" => nil
      })

    assert result == {:error, :overlap}
  end
end
