defmodule FirmowidWeb.Management.Views.ProjectsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker
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

  test "admin can create, edit, archive and restore a project", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    {:ok, new_lv, new_html} = live(conn, ~p"/zarzadzanie/projekty/dodaj")

    assert new_html =~ "Nowy projekt"

    new_lv
    |> form("form[phx-submit='save'][phx-change='validate']", %{
      "project" => %{"name" => "Projekt testowy"}
    })
    |> render_submit()

    project = get_project_by_name!(admin, "Projekt testowy")

    assert_redirect(new_lv, ~p"/zarzadzanie/projekty/#{project.id}")

    {:ok, _show_lv, show_html} = live(conn, ~p"/zarzadzanie/projekty/#{project.id}")

    assert show_html =~ "Projekt testowy"
    assert show_html =~ "Archiwizuj"

    {:ok, edit_lv, edit_html} = live(conn, ~p"/zarzadzanie/projekty/#{project.id}/edycja")

    assert edit_html =~ "Edycja projektu"

    edit_lv
    |> form("form[phx-submit='save'][phx-change='validate']", %{
      "project" => %{"name" => "Projekt po edycji"}
    })
    |> render_submit()

    assert_redirect(edit_lv, ~p"/zarzadzanie/projekty/#{project.id}")

    {:ok, show_lv, updated_show_html} = live(conn, ~p"/zarzadzanie/projekty/#{project.id}")

    assert updated_show_html =~ "Projekt po edycji"

    show_lv
    |> element("button", "Archiwizuj")
    |> render_click()

    assert render(show_lv) =~ "zarchiwizowany"
    assert render(show_lv) =~ "Przywróć projekt"

    {:ok, _archive_lv, archive_html} = live(conn, ~p"/zarzadzanie/projekty/archiwum")

    assert archive_html =~ "Projekt po edycji"

    {:ok, archive_lv, _archive_html} = live(conn, ~p"/zarzadzanie/projekty/archiwum")

    archive_lv
    |> element("button[phx-click='unarchive_project'][phx-value-id='#{project.id}']")
    |> render_click()

    {:ok, _active_lv, active_html} = live(conn, ~p"/zarzadzanie/projekty")

    assert active_html =~ "Projekt po edycji"
  end

  defp current_scope(admin) do
    %Scope{actor: admin, tenant: admin.organization_id}
  end

  defp get_project_by_name!(admin, name) do
    %{}
    |> Timetracker.list_projects!(scope: current_scope(admin))
    |> Enum.find(&(&1.name == name))
    |> Kernel.||(raise "expected project named #{inspect(name)} to exist")
  end
end
