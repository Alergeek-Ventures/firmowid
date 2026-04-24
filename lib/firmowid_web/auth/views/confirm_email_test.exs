defmodule FirmowidWeb.Auth.Views.ConfirmEmailTest do
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.AuthEmailHelpers
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Firmowid.Ash.Core

  setup :set_swoosh_global

  test "user can confirm email from emailed link", %{conn: conn} do
    {:ok, registration_lv, _html} = live(conn, ~p"/zarejestruj")

    email = unique_user_email()

    registration_form =
      form(registration_lv, "#registration_form", user: valid_user_attributes(email: email))

    render_submit(registration_form)
    registration_conn = follow_trigger_action(registration_form, conn)

    assert redirected_to(registration_conn) == ~p"/czasosledz"

    user = Core.get_user_by_email!(email, authorize?: false)
    assert is_nil(user.confirmed_at)

    confirmation_token = extract_token_from_email!("/potwierdz-email/")

    assert {:ok, confirm_lv, html} =
             live(build_conn(), ~p"/potwierdz-email/#{confirmation_token}")

    assert html =~ "Potwierdź adres email"

    confirm_conn =
      confirm_lv
      |> form("#confirm_email_form", user: %{"confirm" => confirmation_token})
      |> submit_form(build_conn())

    assert redirected_to(confirm_conn) == ~p"/czasosledz"

    confirmed_user = Core.get_user_by_email!(email, authorize?: false)
    assert confirmed_user.confirmed_at
  end
end
