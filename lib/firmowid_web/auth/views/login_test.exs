defmodule FirmowidWeb.Auth.Views.LoginTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/zaloguj")

      assert html =~ "Zaloguj"
      assert html =~ "Nie masz konta?"
      assert html =~ "Zapomniałeś hasła?"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/zaloguj")
        |> follow_redirect(conn, "/czasosledz")

      assert {:ok, _conn} = result
    end
  end

  describe "user login" do
    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/zaloguj")

      form =
        form(lv, "#login_form", user: %{email: "test@email.com", password: "123456", remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == "/zaloguj"
    end

    test "offers a Google button for each state of the Remember me box", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/zaloguj")

      assert has_element?(lv, "#remember-me[type=checkbox]")
      assert has_element?(lv, ~s|a[href="/auth/user/google"]|)
      assert has_element?(lv, ~s|a[href="/auth/user/google?remember_me=true"]|)
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/zaloguj")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Zarejestruj się")
        |> render_click()
        |> follow_redirect(conn, ~p"/zarejestruj")

      assert login_html =~ "Zaloguj się"
    end

    test "redirects to forgot password page when the Forgot Password button is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/zaloguj")

      {:ok, conn} =
        lv
        |> element("main a", "Zapomniałeś hasła?")
        |> render_click()
        |> follow_redirect(conn, ~p"/resetuj-haslo")

      assert conn.resp_body =~ "Nie pamiętasz hasła?"
    end
  end
end
