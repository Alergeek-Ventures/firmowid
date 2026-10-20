defmodule FirmowidWeb.Management.Views.AccessTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias FirmowidUI.Utilities.ForbiddenError

  test "non-admin is redirected away from management routes", %{conn: conn} do
    admin = admin_fixture()
    invoicing_user = user_in_org_fixture(admin.organization_id, %{role: :invoicing})

    conn = log_in_user(conn, invoicing_user)

    assert {:error, {:redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/zarzadzanie/pracownicy")

    assert to == ~p"/czasosledz"
    assert flash["error"] =~ "Nie masz dostępu do sekcji zarządzania."
  end

  test "an admin opens employees and invites, an employee cannot", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    admin_conn = log_in_user(conn, admin)
    assert {:ok, _view, _html} = live(admin_conn, ~p"/zarzadzanie/pracownicy")
    assert {:ok, _view, _html} = live(admin_conn, ~p"/zaproszenia")

    employee_conn = log_in_user(build_conn(), employee)
    assert {:error, {:redirect, %{to: to}}} = live(employee_conn, ~p"/zarzadzanie/pracownicy")
    assert to == ~p"/czasosledz"

    assert_raise ForbiddenError, fn -> live(employee_conn, ~p"/zaproszenia") end
  end
end
