defmodule Firmowid.TimetrackerTest do
  use Firmowid.DataCase
  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session

  test "lists projects with users" do
    user = user_fixture()

    {:ok, _} =
      Timetracker.create_project(%{name: "test project", organization_id: user.organization_id})

    project_list = Timetracker.list_projects_with_users()

    [project] = project_list

    assert project.name == "test project"
    assert project.users == []

    {:ok, _} = Timetracker.add_user_to_project(user.id, project.id)

    user =
      user
      |> Repo.preload(:projects)

    [users_project] = user.projects

    assert users_project.id == project.id
    assert users_project.name == "test project"

    project_list_updated = Timetracker.list_projects_with_users()

    [project_updated] = project_list_updated

    assert project_updated.name == "test project"
    assert length(project_updated.users) == 1
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
          start_datetime: ~U[2025-04-01 00:00:00Z],
          end_datetime: ~U[2025-04-01 01:00:00Z]
        },
        %{
          user_id: user1.id,
          project_id: project.id,
          start_datetime: ~U[2025-04-01 00:00:00Z],
          end_datetime: ~U[2025-04-01 01:00:00Z]
        }
      ]

      duration =
        sessions
        |> Enum.map(&Session.put_duration/1)
        |> Enum.reduce(0, fn session, acc ->
          acc + session.duration
        end)

      sessions
      |> Enum.each(&session_fixture(&1))

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
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
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
      start_datetime: ~U[2025-05-01 00:00:00Z],
      end_datetime: ~U[2025-05-01 02:00:00Z]
    })

    session_fixture(%{
      user_id: user.id,
      project_id: project2.id,
      start_datetime: ~U[2025-04-01 00:00:00Z],
      end_datetime: ~U[2025-04-01 02:00:00Z]
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
end
