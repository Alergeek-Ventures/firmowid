defmodule FirmowidWeb.Timetracker.Controllers.CsvTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  test "project csv exports session rows with expected columns", %{conn: conn} do
    admin = admin_fixture()
    project = project_fixture(%{organization_id: admin.organization_id, name: "CSV Project"})

    user_project_fixture(admin.id, project.id, admin.organization_id)

    session_fixture(%{
      organization_id: admin.organization_id,
      project_id: project.id,
      user_id: admin.id,
      title: "Session title",
      start_datetime: ~U[2026-04-02 09:00:00Z],
      end_datetime: ~U[2026-04-02 11:30:00Z]
    })

    conn = log_in_user(conn, admin)

    conn = get(conn, ~p"/czasosledz/projekty/#{project.id}/csv?miesiac=4&rok=2026")

    assert conn.status == 200
    assert conn |> get_resp_header("content-type") |> Enum.join(";") =~ "text/csv"
    assert conn.resp_body =~ "Użytkownik,Data,Czas trwania,Tytuł"
    assert conn.resp_body =~ "Session title"
    assert conn.resp_body =~ "2026-04-02"
  end
end
