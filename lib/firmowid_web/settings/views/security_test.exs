defmodule FirmowidWeb.Settings.Views.SecurityTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.Test.Support.AuthEmailHelpers
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers, as: AuthHelpers
  alias Firmowid.Core

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

  test "a user without a password closes the account with a confirmation only", %{conn: conn} do
    user = admin_fixture()
    organization_id = user.member.organization_id

    # An account created through Google sign-in has no password.
    Ash.Seed.update!(user, %{hashed_password: nil})

    assert {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/ustawienia/konto")

    refute has_element?(view, "#confirm_modal input[type=password]")

    view |> element("#confirm_modal button", "Zamknij konto") |> render_click()

    assert_redirect(view, ~p"/")
    assert {:error, %Invalid{}} = Core.get_user(user.id, authorize?: false)

    assert {:error, %Invalid{}} =
             Core.get_organization(organization_id, authorize?: false)
  end

  describe "closing the account needs a recent sign-in" do
    test "a session signed in long ago is sent to sign in again, and the server refuses it",
         %{conn: conn} do
      user = admin_fixture()
      eleven_minutes_ago = System.system_time(:second) - 11 * 60
      {:ok, token, _claims} = Jwt.token_for_user(user, %{"iat" => eleven_minutes_ago})

      conn =
        conn
        |> init_test_session(%{})
        |> AuthHelpers.store_in_session(Ash.Resource.put_metadata(user, :token, token))

      assert {:ok, view, _html} = live(conn, ~p"/ustawienia/konto")

      assert has_element?(view, "#confirm_modal #sign_in_again_form button[type=submit]")
      refute has_element?(view, "#confirm_modal button", "Zamknij konto")

      # The event the hidden button would send, sent directly.
      assert {:error, {:live_redirect, %{to: "/ustawienia/konto"}}} =
               render_click(view, "delete_account")

      assert {:ok, _user} = Core.get_user(user.id, authorize?: false)

      conn = post(conn, ~p"/zaloguj-ponownie")

      assert redirected_to(conn) == ~p"/zaloguj"
      assert get_session(conn, :return_to) == ~p"/ustawienia/konto"
      refute get_session(conn, :user_token)
      # Without this the remember-me cookie would sign the browser straight back in.
      assert %{max_age: 0} = conn.resp_cookies["remember_me"]
    end

    test "a session restored from the remember-me cookie does not count", %{conn: conn} do
      user = admin_fixture()

      {:ok, remember_me_token, _claims} =
        Jwt.token_for_user(user, %{"purpose" => "remember_me"}, purpose: :remember_me)

      conn =
        conn
        |> init_test_session(%{})
        |> put_req_cookie("remember_me", remember_me_token)

      assert {:ok, view, _html} = live(conn, ~p"/ustawienia/konto")

      assert has_element?(view, "#confirm_modal #sign_in_again_form")

      assert {:error, {:live_redirect, %{to: "/ustawienia/konto"}}} =
               render_click(view, "delete_account")

      assert {:ok, _user} = Core.get_user(user.id, authorize?: false)
    end

    test "an account without a password changes its email only right after signing in",
         %{conn: conn} do
      user = Ash.Seed.update!(admin_fixture(), %{hashed_password: nil})
      claims = %{"iat" => System.system_time(:second) - 11 * 60}
      {:ok, token, _claims} = Jwt.token_for_user(user, claims)

      conn =
        conn
        |> init_test_session(%{})
        |> AuthHelpers.store_in_session(Ash.Resource.put_metadata(user, :token, token))

      assert {:ok, view, _html} = live(conn, ~p"/ustawienia/konto")

      view
      |> element("button[aria-label='Edytuj dane dostępowe']")
      |> render_click()

      drain_sent_emails()
      view |> form("#email_form", user: %{email: unique_user_email()}) |> render_submit()

      # The address moves only when the link sent to it is confirmed, so a request
      # that got through shows as that e-mail.
      refute_email_sent()

      # The page asks first; the action refuses on its own too.
      stale = Ash.Resource.put_metadata(user, :token_claims, claims)

      assert {:error, %Forbidden{}} =
               Core.change_email(stale, %{email: unique_user_email()}, actor: stale)

      new_email = unique_user_email()
      fresh = with_session_claims(user)
      assert {:ok, _user} = Core.change_email(fresh, %{email: new_email}, actor: fresh)
      assert_email_sent(to: new_email)
    end
  end
end
