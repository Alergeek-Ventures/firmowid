defmodule FirmowidWeb.Management.Views.ProjectsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Timetracker.Project

  test "renders active projects list when project has no counterparty", %{conn: conn} do
    admin = admin_fixture()
    project_fixture(%{organization_id: admin.organization_id, name: "No Counterparty"})

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/zarzadzanie/projekty")
    assert html =~ "No Counterparty"
  end

  test "renders archived projects list when project has no counterparty", %{conn: conn} do
    admin = admin_fixture()

    project =
      project_fixture(%{organization_id: admin.organization_id, name: "Archived No Counterparty"})

    {:ok, _archived} =
      Project.archive(project,
        tenant: admin.organization_id,
        actor: admin
      )

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/zarzadzanie/projekty/archiwum")
    assert html =~ "Archived No Counterparty"
  end
end
