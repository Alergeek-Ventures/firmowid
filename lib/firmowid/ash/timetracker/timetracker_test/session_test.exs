defmodule Firmowid.Ash.Timetracker.SessionTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Ash.Timetracker.Session, as: AshSession

  setup do
    user = user_fixture()
    project = project_fixture(%{organization_id: user.organization_id})
    user_project_fixture(user.id, project.id)

    scope = %Firmowid.Ash.Scope{
      current_user: user,
      current_tenant: user.organization_id
    }

    %{user: user, project: project, scope: scope}
  end

  describe "create/2" do
    test "creates a session with valid params", %{user: user, project: project, scope: scope} do
      {:ok, session} =
        AshSession.create(
          %{
            title: "Working on feature",
            project_id: project.id,
            user_id: user.id,
            start_datetime: ~U[2025-04-01 09:00:00Z]
          },
          scope: scope
        )

      assert session.title == "Working on feature"
      assert session.project_id == project.id
      assert session.user_id == user.id
      assert is_nil(session.end_datetime)
    end

    test "creates a session with end_datetime", %{user: user, project: project, scope: scope} do
      {:ok, session} =
        AshSession.create(
          %{
            title: "Completed task",
            project_id: project.id,
            user_id: user.id,
            start_datetime: ~U[2025-04-01 09:00:00Z],
            end_datetime: ~U[2025-04-01 10:00:00Z]
          },
          scope: scope
        )

      assert session.end_datetime == ~U[2025-04-01 10:00:00Z]
    end

    test "rejects session with end before start", %{user: user, project: project, scope: scope} do
      assert {:error, _} =
               AshSession.create(
                 %{
                   title: "Bad times",
                   project_id: project.id,
                   user_id: user.id,
                   start_datetime: ~U[2025-04-01 10:00:00Z],
                   end_datetime: ~U[2025-04-01 09:00:00Z]
                 },
                 scope: scope
               )
    end
  end

  describe "stop/2" do
    test "stops a running session by setting end_datetime", %{
      user: user,
      project: project,
      scope: scope
    } do
      {:ok, session} =
        AshSession.create(
          %{
            title: "Running",
            project_id: project.id,
            user_id: user.id,
            start_datetime: DateTime.utc_now()
          },
          scope: scope
        )

      assert is_nil(session.end_datetime)

      {:ok, stopped} = AshSession.stop(session, scope: scope)

      assert stopped.end_datetime
    end
  end

  describe "update/3" do
    test "updates session title", %{user: user, project: project, scope: scope} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Old Title"
        })

      {:ok, updated} = AshSession.update(session, %{title: "New Title"}, scope: scope)

      assert updated.title == "New Title"
    end
  end

  describe "destroy/2" do
    test "deletes a session", %{user: user, project: project, scope: scope} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id
        })

      assert :ok = AshSession.destroy(session, scope: scope)
      assert is_nil(Repo.get(AshSession, session.id))
    end
  end

  describe "overlap prevention" do
    test "prevents overlapping sessions for the same user", %{
      user: user,
      project: project,
      scope: scope
    } do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      result =
        AshSession.create(
          %{
            title: "Overlap",
            project_id: project.id,
            user_id: user.id,
            start_datetime: ~U[2025-04-01 00:30:00Z],
            end_datetime: ~U[2025-04-01 01:30:00Z]
          },
          scope: scope
        )

      assert {:error, _} = result
    end

    test "prevents overlapping ongoing sessions", %{user: user, project: project, scope: scope} do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z]
      })

      result =
        AshSession.create(
          %{
            title: "Overlap",
            project_id: project.id,
            user_id: user.id,
            start_datetime: ~U[2025-04-01 00:30:00Z]
          },
          scope: scope
        )

      assert {:error, _} = result
    end
  end

  describe "total_time_worked/2" do
    test "returns 0 when no sessions exist", %{scope: scope} do
      {:ok, result} = AshSession.total_time_worked(%{month: 4, year: 2025}, scope: scope)
      assert result == 0
    end

    test "sums durations for a given month", %{user: user, project: project, scope: scope} do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      {:ok, result} = AshSession.total_time_worked(%{month: 4, year: 2025}, scope: scope)
      assert result == 3600
    end

    test "does not include sessions from other months", %{
      user: user,
      project: project,
      scope: scope
    } do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      {:ok, result} = AshSession.total_time_worked(%{month: 5, year: 2025}, scope: scope)
      assert result == 0
    end

    test "sums across multiple sessions and users", %{user: user, project: project, scope: scope} do
      user2 = user_in_org_fixture(user.organization_id)
      user_project_fixture(user2.id, project.id)

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 02:00:00Z],
        end_datetime: ~U[2025-04-01 03:00:00Z]
      })

      session_fixture(%{
        user_id: user2.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      {:ok, result} = AshSession.total_time_worked(%{month: 4, year: 2025}, scope: scope)
      assert result == 3 * 3600
    end
  end

  describe "months_with_sessions/2" do
    test "returns empty when no sessions", %{scope: scope} do
      {:ok, result} = AshSession.months_with_sessions(%{}, scope: scope)
      assert result == []
    end

    test "returns distinct months", %{user: user, project: project, scope: scope} do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-02 00:00:00Z],
        end_datetime: ~U[2025-04-02 01:00:00Z]
      })

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-05-01 00:00:00Z],
        end_datetime: ~U[2025-05-01 01:00:00Z]
      })

      {:ok, months} = AshSession.months_with_sessions(%{}, scope: scope)

      month_dates = Enum.map(months, &NaiveDateTime.truncate(&1, :second))

      assert length(month_dates) == 2
      assert ~N[2025-04-01 00:00:00] in month_dates
      assert ~N[2025-05-01 00:00:00] in month_dates
    end
  end

  describe "most_demanding_project/2" do
    test "returns nil when no sessions", %{scope: scope} do
      {:ok, result} = AshSession.most_demanding_project(4, 2025, scope: scope)
      assert is_nil(result)
    end

    test "returns project with most hours", %{user: user, project: project, scope: scope} do
      project2 = project_fixture(%{organization_id: user.organization_id})
      user_project_fixture(user.id, project2.id)

      # project1: 1h
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z]
      })

      # project2: 2h
      session_fixture(%{
        user_id: user.id,
        project_id: project2.id,
        start_datetime: ~U[2025-04-01 03:00:00Z],
        end_datetime: ~U[2025-04-01 05:00:00Z]
      })

      {:ok, result} = AshSession.most_demanding_project(4, 2025, scope: scope)

      assert result.project.id == project2.id
      assert result.time_worked == 2 * 3600
    end
  end
end
