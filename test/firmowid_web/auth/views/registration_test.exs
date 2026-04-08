defmodule FirmowidWeb.Auth.Views.RegistrationTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/zarejestruj")

      assert html =~ "Stwórz konto"
      assert html =~ "Zaloguj się"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/zarejestruj")
        |> follow_redirect(conn, "/czasosledz")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/zarejestruj")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "", "password" => ""})

      assert result =~ "Stwórz konto"
      assert result =~ "Coś poszło nie tak..."
    end
  end

  describe "register user" do
    test "creates account and logs the user in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/zarejestruj")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/czasosledz"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/zarejestruj")

      user = user_fixture(%{email: "test@email.com"})

      form =
        form(lv, "#registration_form", user: %{"email" => user.email, "password" => "valid_password"})

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/zarejestruj"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Taki email jest już zajęty."
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/zarejestruj")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Zaloguj się")
        |> render_click()
        |> follow_redirect(conn, ~p"/zaloguj")

      assert login_html =~ "Zaloguj się"
    end
  end
end
