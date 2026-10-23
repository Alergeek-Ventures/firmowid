defmodule FirmowidWeb.Timetracker.Controllers.CsvTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.Session

  test "project csv exports session rows with expected columns", %{conn: conn} do
    admin = admin_fixture()
    employee = user_fixture(%{organization_id: admin.member.organization_id})

    project =
      project_fixture(%{organization_id: admin.member.organization_id, name: "CSV Project"})

    user_project_fixture(employee.id, project.id, admin.member.organization_id)

    Session.create!(
      %{
        project_id: project.id,
        member_id: employee.member.id,
        title: "=1+1",
        start_datetime: ~U[2026-04-02 09:00:00Z],
        end_datetime: ~U[2026-04-02 11:30:00Z]
      },
      scope: Scope.new!(employee, employee.member.organization_id)
    )

    conn = log_in_user(conn, admin)

    conn = get(conn, ~p"/czasosledz/projekty/#{project.id}/csv?miesiac=4&rok=2026")

    assert conn.status == 200
    assert conn |> get_resp_header("content-type") |> Enum.join(";") =~ "text/csv"
    assert conn.resp_body =~ "Użytkownik,Data,Czas trwania,Tytuł"
    assert conn.resp_body =~ "'=1+1"
    assert conn.resp_body =~ "2026-04-02"
  end
end
