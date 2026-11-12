defmodule FirmowidWeb.Settings.Views.SecurityTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

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
  end
end
