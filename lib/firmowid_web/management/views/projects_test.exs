defmodule FirmowidWeb.Management.Views.ProjectsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true
  use Gettext, backend: Firmowid.Gettext

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Scope
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project

  test "renders active projects list when project has no counterparty", %{conn: conn} do
    admin = admin_fixture()
    project_fixture(%{organization_id: admin.member.organization_id, name: "No Counterparty"})

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/zarzadzanie/projekty")
    assert html =~ "No Counterparty"
  end

  test "renders archived projects list when project has no counterparty", %{conn: conn} do
    admin = admin_fixture()

    project =
      project_fixture(%{
        organization_id: admin.member.organization_id,
        name: "Archived No Counterparty"
      })

    {:ok, _archived} =
      Project.archive(project,
        tenant: admin.member.organization_id,
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

  test "admin deletes an archived project only when it has no recorded time", %{conn: conn} do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    conn = log_in_user(conn, admin)

    with_time = project_fixture(%{organization_id: org_id, name: "With Time"})
    session_fixture(%{organization_id: org_id, project_id: with_time.id, user_id: admin.id})
    {:ok, _} = Project.archive(with_time, tenant: org_id, actor: admin)

    {:ok, lv, _html} = live(conn, ~p"/zarzadzanie/projekty/#{with_time.id}")
    lv |> element("button[phx-click='delete_project']") |> render_click()

    assert render(lv) =~ gettext("A project with recorded time cannot be deleted.")
    assert get_project_by_name!(admin, "With Time")

    without_time = project_fixture(%{organization_id: org_id, name: "Without Time"})
    {:ok, _} = Project.archive(without_time, tenant: org_id, actor: admin)

    {:ok, lv, _html} = live(conn, ~p"/zarzadzanie/projekty/#{without_time.id}")
    lv |> element("button[phx-click='delete_project']") |> render_click()

    assert_redirect(lv)

    refute Enum.any?(
             Timetracker.list_projects!(%{}, scope: current_scope(admin)),
             &(&1.name == "Without Time")
           )
  end

  defp current_scope(admin) do
    %Scope{actor: admin, tenant: admin.member.organization_id}
  end

  defp get_project_by_name!(admin, name) do
    %{}
    |> Timetracker.list_projects!(scope: current_scope(admin))
    |> Enum.find(&(&1.name == name))
    |> Kernel.||(raise "expected project named #{inspect(name)} to exist")
  end
end
