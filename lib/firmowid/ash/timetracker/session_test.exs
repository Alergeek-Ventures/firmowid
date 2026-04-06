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
          title: "Old Title",
          organization_id: user.organization_id
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
