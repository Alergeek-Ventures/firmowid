defmodule FirmowidWeb.UserForgotPasswordLiveTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Accounts
  alias Firmowid.Repo

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
    setup do
      %{user: user_fixture()}
    end

    test "sends a new reset password token", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => user.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Jeśli Twój email jest w naszym systemie"

      assert Repo.get_by!(Accounts.UserToken, [user_id: user.id], skip_organization_id: true).context ==
               "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{"email" => "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Jeśli Twój email jest w naszym systemie"
      assert Repo.all(Accounts.UserToken, skip_organization_id: true) == []
    end
  end
end
