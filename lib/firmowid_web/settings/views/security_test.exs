defmodule FirmowidWeb.Settings.Views.SecurityTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Ash.Error.Invalid
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
end
