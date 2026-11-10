defmodule FirmowidWeb.Auth.Views.RegistrationTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Core

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
      assert result =~ "Hasło musi mieć co najmniej 8 znaków."
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
      assert Phoenix.Flash.get(conn.assigns.flash, :email_error) == "Taki email jest już zajęty."
    end

    test "creates account and organization", %{conn: conn} do
      # The VAT white list does not know the NIP, so the owner enters the details.
      Req.Test.stub(:nip_api, &Req.Test.json(&1, %{"result" => %{"subject" => nil}}))

      {:ok, registration_lv, _html} = live(conn, ~p"/zarejestruj")

      email = unique_user_email()

      registration_form =
        form(registration_lv, "#registration_form", user: valid_user_attributes(email: email))

      render_submit(registration_form)
      conn = follow_trigger_action(registration_form, conn)

      assert redirected_to(conn) == ~p"/czasosledz"

      {:ok, _start_lv, start_html} = live(conn, ~p"/organizacja")

      assert start_html =~ "Zakładam firmę"

      {:ok, organization_lv, _html} = live(conn, ~p"/organizacja?krok=firma")

      organization_lv |> form("#company-form", %{"nip" => "5261040828"}) |> render_change()
      assert render_async(organization_lv) =~ "Biała lista VAT nie zna tego NIP-u."

      company = %{
        "nip" => "5261040828",
        "name" => "Nowa Organizacja",
        "address" => "Prosta 1, 00-001 Warszawa"
      }

      blank_name_html =
        organization_lv
        |> form("#company-form", Map.put(company, "owner_name", "   "))
        |> render_submit()

      assert blank_name_html =~ "Wpisz swoje imię i nazwisko."

      organization_lv
      |> form("#company-form", Map.put(company, "owner_name", "Ada Lovelace"))
      |> render_submit()

      assert_patch(organization_lv, ~p"/organizacja?krok=branza")
      assert is_nil(Core.load_member(Core.get_user_by_email!(email, authorize?: false)).member)

      organization_lv
      |> form("#industry-form", %{"industry" => "services", "bills_hourly" => "false"})
      |> render_submit()

      created_user = email |> Core.get_user_by_email!(authorize?: false) |> Core.load_member()

      organization =
        Core.get_organization!(created_user.member.organization_id, authorize?: false)

      assert organization.name == "Nowa Organizacja"
      assert organization.owner_id == created_user.id
      refute organization.bills_hourly
      assert created_user.member.name == "Ada Lovelace"

      conn = organization_lv |> form("#switch-organization-form") |> follow_trigger_action(conn)

      assert redirected_to(conn) == ~p"/pierwsze-kroki"

      # Until the first steps are done, the rest of the app leads back to them.
      assert {:error, {:redirect, %{to: "/pierwsze-kroki"}}} = live(conn, ~p"/fakturowanie")
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

      {:ok, organization_lv, _html} = live(conn, ~p"/organizacja?krok=dolacz")

      # Typing a valid code shows which company invites before joining.
      code_html =
        organization_lv
        |> form("#join_form", %{"name" => "", "code" => invite_code})
        |> render_change()

      organization = Core.get_organization!(admin.member.organization_id, authorize?: false)
      assert code_html =~ "zaprasza Cię do swojego zespołu."
      assert code_html =~ organization.name

      blank_name_html =
        organization_lv
        |> form("#join_form", %{"name" => "   ", "code" => invite_code})
        |> render_submit()

      assert blank_name_html =~ "Wpisz swoje imię i nazwisko."
      assert is_nil(Core.load_member(Core.get_user_by_email!(email, authorize?: false)).member)

      organization_lv
      |> form("#join_form", %{"name" => "Grace Hopper", "code" => invite_code})
      |> render_submit()

      joined_user = email |> Core.get_user_by_email!(authorize?: false) |> Core.load_member()

      assert joined_user.member.organization_id == admin.member.organization_id
      assert joined_user.member.name == "Grace Hopper"
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
