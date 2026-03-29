defmodule FirmowidWeb.Auth.Views.ResetPasswordTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Accounts

  setup do
    user = user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    %{token: token, user: user}
  end

  describe "Reset password page" do
    test "renders reset password with valid token", %{conn: conn, token: token} do
      {:ok, _lv, html} = live(conn, ~p"/resetuj-haslo/#{token}")

      assert html =~ "Resetuj hasło"
    end

    test "does not render reset password with invalid token", %{conn: conn} do
      {:error, {:redirect, to}} = live(conn, ~p"/resetuj-haslo/invalid")

      assert to == %{
               flash: %{"error" => "Link do resetowania hasła jest nieprawidłowy lub wygasł."},
               to: ~p"/"
             }
    end

    test "renders errors for invalid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo/#{token}")

      result =
        lv
        |> element("#reset_password_form")
        |> render_change(user: %{"password" => "secret12", "password_confirmation" => "secret123456"})

      assert result =~ "should be at least 12 character"
      assert result =~ "does not match password"
    end
  end

  describe "Reset Password" do
    test "resets password once", %{conn: conn, token: token, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo/#{token}")

      {:ok, conn} =
        lv
        |> form("#reset_password_form",
          user: %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/zaloguj")

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Hasło zostało zresetowane pomyślnie"
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not reset password on invalid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo/#{token}")

      result =
        lv
        |> form("#reset_password_form",
          user: %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        )
        |> render_submit()

      assert result =~ "Resetuj hasło"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "Reset password navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo/#{token}")

      {:ok, conn} =
        lv
        |> element("main a", "Zaloguj się")
        |> render_click()
        |> follow_redirect(conn, ~p"/zaloguj")

      assert conn.resp_body =~ "Zaloguj się"
    end

    test "redirects to registration page when the Register button is clicked", %{
      conn: conn,
      token: token
    } do
      {:ok, lv, _html} = live(conn, ~p"/resetuj-haslo/#{token}")

      {:ok, conn} =
        lv
        |> element("main a", "Zarejestruj się")
        |> render_click()
        |> follow_redirect(conn, ~p"/zarejestruj")

      assert conn.resp_body =~ "Stwórz konto"
    end
  end
end
