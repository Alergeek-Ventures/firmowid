defmodule Firmowid.Ash.Timetracker.SessionTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.Session, as: AshSession

  setup do
    user = user_fixture()
    project = project_fixture(%{organization_id: user.organization_id})
    user_project_fixture(user.id, project.id, user.organization_id)

    scope = %Scope{
      actor: user,
      tenant: user.organization_id
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

    test "normalizes explicit boundaries to minutes", %{
      user: user,
      project: project,
      scope: scope
    } do
      {:ok, session} =
        AshSession.create(
          %{
            title: "Completed task",
            project_id: project.id,
            user_id: user.id,
            start_datetime: ~U[2025-04-01 09:00:42Z],
            end_datetime: ~U[2025-04-01 10:00:17Z]
          },
          scope: scope
        )

      assert session.start_datetime == ~U[2025-04-01 09:00:00Z]
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
      project: project,
      scope: scope
    } do
      {:ok, session} =
        AshSession.start(
          %{
            title: "Running",
            project_id: project.id
          },
          scope: scope
        )

      assert is_nil(session.end_datetime)

      {:ok, stopped} = AshSession.stop(session, scope: scope)

      assert stopped.start_datetime.second == 0
      assert stopped.end_datetime.second == 0
    end
  end

  describe "stop_current/1" do
    test "stops the actor's running session without a client-supplied id", %{
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

      {:ok, stopped} = AshSession.stop_current(scope: scope)

      assert stopped.id == session.id
      assert stopped.end_datetime
      assert is_nil(AshSession.get_current!(scope: scope))
    end

    test "returns nil when the actor has no running session", %{scope: scope} do
      assert {:ok, nil} = AshSession.stop_current(scope: scope)
    end
  end

  describe "update/3" do
    test "updates session title", %{user: user, project: project, scope: scope} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Old Title",
          organization_id: user.organization_id
        })

      {:ok, updated} = AshSession.update(session, %{title: "New Title"}, scope: scope)

      assert updated.title == "New Title"
    end

    test "normalizes legacy second-precision boundaries when editing", %{
      user: user,
      project: project,
      scope: scope
    } do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.organization_id
        })

      Repo.query!(
        """
        UPDATE sessions
        SET start_datetime = '2025-04-01 09:00:42Z', end_datetime = '2025-04-01 10:00:17Z'
        WHERE id::text = $1
        """,
        [session.id]
      )

      session = Repo.get!(AshSession, session.id)

      {:ok, updated} = AshSession.update(session, %{title: "Edited legacy session"}, scope: scope)

      assert updated.start_datetime == ~U[2025-04-01 09:00:00Z]
      assert updated.end_datetime == ~U[2025-04-01 10:00:00Z]
    end

    test "keeps adjacent sessions editable with minute-only boundaries", %{
      user: user,
      project: project,
      scope: scope
    } do
      first_session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "First",
          start_datetime: ~U[2025-04-01 09:00:42Z],
          end_datetime: ~U[2025-04-01 10:00:17Z],
          organization_id: user.organization_id
        })

      second_session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Second",
          start_datetime: ~U[2025-04-01 10:00:00Z],
          end_datetime: ~U[2025-04-01 11:00:00Z],
          organization_id: user.organization_id
        })

      {:ok, updated} =
        AshSession.update(
          second_session,
          %{
            title: "Edited second",
            start_datetime: ~U[2025-04-01 10:00:00Z],
            end_datetime: ~U[2025-04-01 11:00:00Z]
          },
          scope: scope
        )

      assert first_session.end_datetime == updated.start_datetime
      assert updated.title == "Edited second"
    end
  end

  describe "destroy/2" do
    test "deletes a session", %{user: user, project: project, scope: scope} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.organization_id
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
        end_datetime: ~U[2025-04-01 01:00:00Z],
        organization_id: user.organization_id
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
        start_datetime: ~U[2025-04-01 00:00:00Z],
        organization_id: user.organization_id
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
end
