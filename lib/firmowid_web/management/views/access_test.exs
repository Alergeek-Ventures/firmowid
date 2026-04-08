defmodule FirmowidWeb.Management.Views.AccessTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  test "non-admin is redirected away from management routes", %{conn: conn} do
    admin = admin_fixture()
    invoicing_user = user_in_org_fixture(admin.organization_id, %{role: :invoicing})

    conn = log_in_user(conn, invoicing_user)

    assert {:error, {:redirect, %{to: to, flash: flash}}} = live(conn, ~p"/zarzadzanie/pracownicy")

    assert to == ~p"/czasosledz"
    assert flash["error"] =~ "Nie masz dostępu do sekcji zarządzania."
  end
end
