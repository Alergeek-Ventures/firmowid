defmodule FirmowidWeb.Auth.Views.ResetPasswordTest do
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.AuthEmailHelpers
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  setup :set_swoosh_global

  test "user can reset password from emailed link", %{conn: conn} do
    user = user_fixture(%{password: "old valid password!!"})
    drain_sent_emails()

    {:ok, forgot_password_lv, _html} = live(conn, ~p"/resetuj-haslo")

    forgot_password_lv
    |> form("#reset_password_form", user: %{"email" => user.email})
    |> submit_form(conn)

    reset_token = extract_token_from_email!("/resetuj-haslo/")

    assert {:ok, reset_password_lv, html} = live(conn, ~p"/resetuj-haslo/#{reset_token}")
    assert html =~ "Resetuj hasło"

    reset_password_form =
      form(reset_password_lv, "#reset_password_form",
        user: %{
          "reset_token" => reset_token,
          "password" => "new valid password!!"
        }
      )

    reset_conn = submit_form(reset_password_form, conn)

    assert redirected_to(reset_conn) == ~p"/czasosledz"
  end
end
