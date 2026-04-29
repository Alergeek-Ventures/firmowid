defmodule FirmowidWeb.Settings.Views.SecurityTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  test "account settings renders password editor inline", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    assert {:ok, view, html} = live(conn, ~p"/ustawienia/konto")
    assert html =~ "Dane dostępowe"

    html =
      view
      |> element("button[aria-label='Edytuj dane dostępowe']")
      |> render_click()

    assert html =~ "Nowe hasło"
  end
end
