defmodule Firmowid.Repo.Migrations.NormalizeSessionBoundariesToMinutesTest do
  use Firmowid.DataCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Ash.Timetracker.Session, as: AshSession
  alias Firmowid.Repo
  alias Firmowid.Repo.Migrations.NormalizeSessionBoundariesToMinutes

  test "normalizes only August 2026 sessions" do
    user = user_fixture()
    project = project_fixture(%{organization_id: user.organization_id})
    user_project_fixture(user.id, project.id, user.organization_id)

    july_session =
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2026-07-31 09:00:42Z],
        end_datetime: ~U[2026-07-31 10:00:17Z],
        organization_id: user.organization_id
      })

    august_session =
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2026-08-01 09:00:42Z],
        end_datetime: ~U[2026-08-01 10:00:17Z],
        organization_id: user.organization_id
      })

    september_session =
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2026-09-01 09:00:42Z],
        end_datetime: ~U[2026-09-01 10:00:17Z],
        organization_id: user.organization_id
      })

    for {session, start_datetime, end_datetime} <- [
          {july_session, ~U[2026-07-31 09:00:42Z], ~U[2026-07-31 10:00:17Z]},
          {august_session, ~U[2026-08-01 09:00:42Z], ~U[2026-08-01 10:00:17Z]},
          {september_session, ~U[2026-09-01 09:00:42Z], ~U[2026-09-01 10:00:17Z]}
        ] do
      Repo.query!(
        "UPDATE sessions SET start_datetime = $1, end_datetime = $2 WHERE id::text = $3",
        [start_datetime, end_datetime, session.id]
      )
    end

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

    assert %{start_datetime: ~U[2026-07-31 09:00:42Z], end_datetime: ~U[2026-07-31 10:00:17Z]} =
             Repo.get!(AshSession, july_session.id)

    assert %{start_datetime: ~U[2026-08-01 09:00:00Z], end_datetime: ~U[2026-08-01 10:00:00Z]} =
             Repo.get!(AshSession, august_session.id)

    assert %{start_datetime: ~U[2026-09-01 09:00:42Z], end_datetime: ~U[2026-09-01 10:00:17Z]} =
             Repo.get!(AshSession, september_session.id)
  end
end
