defmodule FirmowidWeb.Settings.Views.SecurityTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  test "security settings page renders without missing assigns", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/bezpieczenstwo")
    assert html =~ "Zmiana hasła"
  end
end
