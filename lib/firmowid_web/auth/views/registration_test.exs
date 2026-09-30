defmodule FirmowidWeb.Auth.Views.RegistrationTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Core

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
        |> form("#registration_form", user: %{"email" => "", "password" => ""})
        |> render_submit()

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

    test "creates account and organization", %{conn: conn} do
      {:ok, registration_lv, _html} = live(conn, ~p"/zarejestruj")

      email = unique_user_email()

      registration_form =
        form(registration_lv, "#registration_form", user: valid_user_attributes(email: email))

      render_submit(registration_form)
      conn = follow_trigger_action(registration_form, conn)

      assert redirected_to(conn) == ~p"/czasosledz"

      {:ok, organization_lv, organization_html} = live(conn, ~p"/organizacja")

      assert organization_html =~ "Czas na przypisanie organizacji do Twojego konta"

      organization_lv
      |> form("#organization_form", %{
        "organization" => %{
          "nip" => "5261040828",
          "name" => "Nowa Organizacja"
        },
        "address" => %{
          "street" => "Prosta",
          "number" => "1",
          "postal_code" => "00-001",
          "city" => "Warszawa"
        }
      })
      |> render_submit()

      created_user = Core.get_user_by_email!(email, authorize?: false)

      assert created_user.organization_id

      organization = Core.get_organization!(created_user.organization_id, authorize?: false)

      assert organization.name == "Nowa Organizacja"
      assert organization.owner_id == created_user.id

      {:ok, _dashboard_lv, dashboard_html} = live(conn, ~p"/fakturowanie")

      assert dashboard_html =~ "Podepnij konto bankowe"
      assert dashboard_html =~ "Połącz bank"
      assert dashboard_html =~ "Połącz z KSeF"
      assert dashboard_html =~ "Połącz KSeF"
    end

    test "creates account and joins organization", %{conn: conn} do
      admin = admin_fixture()

      admin_conn = log_in_user(conn, admin)

      {:ok, invites_lv, invites_html} = live(admin_conn, ~p"/zaproszenia")

      assert invites_html =~ "Zaproszenia do Twojej organizacji"

      updated_invites_html =
        invites_lv
        |> element("button", "Przygotuj zaproszenie")
        |> render_click()

      [invite_code] =
        Regex.run(~r{<code[^>]*>\s*([^<\s]+)\s*</code>}, updated_invites_html, capture: :all_but_first)

      {:ok, registration_lv, _html} = live(conn, ~p"/zarejestruj")

      email = unique_user_email()

      registration_form =
        form(registration_lv, "#registration_form", user: valid_user_attributes(email: email))

      render_submit(registration_form)
      conn = follow_trigger_action(registration_form, conn)

      assert redirected_to(conn) == ~p"/czasosledz"

      {:ok, organization_lv, organization_html} = live(conn, ~p"/organizacja")

      assert organization_html =~ "Czas na przypisanie organizacji do Twojego konta"

      organization_lv
      |> form("#join_form", %{"code" => invite_code})
      |> render_submit()

      joined_user = Core.get_user_by_email!(email, authorize?: false)

      assert joined_user.organization_id == admin.organization_id
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
