defmodule FirmowidWeb.Management.Views.AccessTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias FirmowidUI.Utilities.ForbiddenError

  test "non-admin is redirected away from management routes", %{conn: conn} do
    admin = admin_fixture()
    invoicing_user = user_in_org_fixture(admin.member.organization_id, %{role: :invoicing})

    conn = log_in_user(conn, invoicing_user)

    assert {:error, {:redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/zarzadzanie/pracownicy")

    assert to == ~p"/fakturowanie"
    assert flash["error"] =~ "Nie masz dostępu do sekcji zarządzania."
  end

  # The pages under /zarzadzanie come from the router, so one added there later
  # cannot be left open; the three outside it are listed by hand.
  test "a non-admin is redirected away from every admin-only page", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})
    conn = log_in_user(conn, employee)

    paths =
      for %{path: path, metadata: %{phoenix_live_view: _live}} <-
            Phoenix.Router.routes(FirmowidWeb.Core.Router),
          String.starts_with?(path, "/zarzadzanie") or
            path in ["/pierwsze-kroki", "/limit-planu", "/ustawienia/bank/dodaj"],
          do: String.replace(path, ~r/:\w+/, Ecto.UUID.generate())

    assert paths != []

    for path <- paths do
      assert {:error, {:redirect, %{to: to}}} = live(conn, path)
      assert to == ~p"/czasosledz", "#{path} let a non-admin in"
    end
  end

  test "an admin opens employees and invites, an employee cannot", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    admin_conn = log_in_user(conn, admin)
    assert {:ok, _view, _html} = live(admin_conn, ~p"/zarzadzanie/pracownicy")
    assert {:ok, _view, _html} = live(admin_conn, ~p"/zaproszenia")

    employee_conn = log_in_user(build_conn(), employee)
    assert {:error, {:redirect, %{to: to}}} = live(employee_conn, ~p"/zarzadzanie/pracownicy")
    assert to == ~p"/czasosledz"

    assert_raise ForbiddenError, fn -> live(employee_conn, ~p"/zaproszenia") end
  end
end
