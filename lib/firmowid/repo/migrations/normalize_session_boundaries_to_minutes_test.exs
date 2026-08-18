defmodule Firmowid.Repo.Migrations.NormalizeSessionBoundariesToMinutesTest do
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias Firmowid.Repo
  alias Firmowid.Repo.Migrations.NormalizeSessionBoundariesToMinutes

  test "backfills historical adjacent and active sessions without introducing conflicts" do
    user = user_fixture()
    project = project_fixture(%{organization_id: user.organization_id})
    user_project_fixture(user.id, project.id, user.organization_id)

    scope = %Scope{actor: user, tenant: user.organization_id}

    first_session =
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 09:00:00Z],
        end_datetime: ~U[2025-04-01 10:00:00Z],
        organization_id: user.organization_id
      })

    second_session =
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 10:00:00Z],
        end_datetime: ~U[2025-04-01 11:00:00Z],
        organization_id: user.organization_id
      })

    active_session =
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 11:00:00Z],
        organization_id: user.organization_id
      })

    # These values model pre-fix production data: the sessions do not overlap,
    # but a minute-only form would submit the second session at 10:00:00.
    Repo.query!(
      "UPDATE sessions SET start_datetime = $1 WHERE id::text = $2",
      [~U[2025-04-01 11:00:42Z], active_session.id]
    )

    Repo.query!(
      """
      UPDATE sessions
      SET start_datetime = $1, end_datetime = $2
      WHERE id::text = $3
      """,
      [~U[2025-04-01 10:00:18Z], ~U[2025-04-01 11:00:19Z], second_session.id]
    )

    Repo.query!(
      """
      UPDATE sessions
      SET start_datetime = $1, end_datetime = $2
      WHERE id::text = $3
      """,
      [~U[2025-04-01 09:00:42Z], ~U[2025-04-01 10:00:17Z], first_session.id]
    )

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      20_260_818_092_248,
      NormalizeSessionBoundariesToMinutes,
      :forward,
      :up,
      :up,
      log: false
    )

    assert %{start_datetime: ~U[2025-04-01 09:00:00Z], end_datetime: ~U[2025-04-01 10:00:00Z]} =
             Repo.get!(AshSession, first_session.id)

    assert %{start_datetime: ~U[2025-04-01 10:00:00Z], end_datetime: ~U[2025-04-01 11:00:00Z]} =
             Repo.get!(AshSession, second_session.id)

    assert %{start_datetime: ~U[2025-04-01 11:00:00Z], end_datetime: nil} =
             Repo.get!(AshSession, active_session.id)

    second_session = Repo.get!(AshSession, second_session.id)
    active_session = Repo.get!(AshSession, active_session.id)

    assert {:ok, %{title: "Edited adjacent session"}} =
             AshSession.update(second_session, %{title: "Edited adjacent session"}, scope: scope)

    assert {:ok, %{end_datetime: ~U[2025-04-01 11:01:00Z]}} =
             AshSession.update(active_session, %{end_datetime: ~U[2025-04-01 11:01:00Z]}, scope: scope)
  end
end
