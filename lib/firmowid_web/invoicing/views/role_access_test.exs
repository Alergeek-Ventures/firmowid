defmodule FirmowidWeb.Invoicing.Views.RoleAccessTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  test "invoicing role can open invoicing hub but cannot start sales invoice creator", %{conn: conn} do
    admin = admin_fixture()
    invoicing_user = user_in_org_fixture(admin.organization_id, %{role: :invoicing})

    conn = log_in_user(conn, invoicing_user)

    assert {:ok, _view, html} = live(conn, ~p"/fakturowanie")
    refute html =~ "Wystaw fakturę"

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/sprzedazowe")
    assert to == ~p"/fakturowanie"
  end

  test "invoicing role can access timetracker", %{conn: conn} do
    admin = admin_fixture()
    invoicing_user = user_in_org_fixture(admin.organization_id, %{role: :invoicing})

    conn = log_in_user(conn, invoicing_user)

    assert {:ok, _view, html} = live(conn, ~p"/czasosledz")
    assert html =~ "Czasośledź"
  end
end
