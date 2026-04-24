defmodule FirmowidWeb.Auth.Views.ForgotPasswordTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "Forgot password page" do
    test "renders email page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/resetuj-haslo")

      assert html =~ "Nie pamiętasz hasła?"
      assert has_element?(lv, ~s|a[href="#{~p"/zarejestruj"}"]|, "Zarejestruj się")
      assert has_element?(lv, ~s|a[href="#{~p"/zaloguj"}"]|, "Zaloguj się")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/resetuj-haslo")
        |> follow_redirect(conn, ~p"/czasosledz")

      assert {:ok, _conn} = result
    end
  end

  describe "Reset link" do
    test "redirects after submitting the reset password form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo")

      form = form(lv, "#reset_password_form", user: %{"email" => "known@example.com"})
      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/zaloguj"
    end

    test "redirects after submitting the reset password form for an unknown email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo")

      form = form(lv, "#reset_password_form", user: %{"email" => "unknown@example.com"})
      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/zaloguj"
    end
  end
end
