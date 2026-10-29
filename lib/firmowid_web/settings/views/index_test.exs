defmodule FirmowidWeb.Settings.Views.IndexTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Core
  alias Firmowid.Finances
  alias Firmowid.Finances.Requisition
  alias Firmowid.Ksef.Credential
  alias Firmowid.Scope

  test "bank accounts are sorted by IBAN and keep order after rename", %{conn: conn} do
    admin = admin_fixture()
    scope = %Scope{actor: admin, tenant: admin.member.organization_id}

    {:ok, account_3} =
      Finances.create_manual_bank_account(
        %{iban: "PL44 1140 2004 0000 3002 0135 5363", name: "Zeta", currency: "PLN"},
        scope: scope
      )

    {:ok, account_1} =
      Finances.create_manual_bank_account(
        %{iban: "PL44 1140 2004 0000 3002 0135 5361", name: "Alpha", currency: "PLN"},
        scope: scope
      )

    {:ok, _account_2} =
      Finances.create_manual_bank_account(
        %{iban: "PL44 1140 2004 0000 3002 0135 5362", name: "Beta", currency: "PLN"},
        scope: scope
      )

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/firma")

    assert iban_position(html, "PL44 1140 2004 0000 3002 0135 5361") <
             iban_position(html, "PL44 1140 2004 0000 3002 0135 5362")

    assert iban_position(html, "PL44 1140 2004 0000 3002 0135 5362") <
             iban_position(html, "PL44 1140 2004 0000 3002 0135 5363")

    assert {:ok, _updated} =
             Finances.update_bank_account(account_1, %{name: "ZZZ renamed"}, scope: scope)

    assert {:ok, _view, html_after_rename} = live(conn, ~p"/ustawienia/firma")

    assert iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5361") <
             iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5362")

    assert iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5362") <
             iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5363")

    assert {:ok, _updated} =
             Finances.update_bank_account(account_3, %{name: "AAA renamed"}, scope: scope)

    assert {:ok, _view, html_after_second_rename} = live(conn, ~p"/ustawienia/firma")

    assert iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5361") <
             iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5362")

    assert iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5362") <
             iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5363")
  end

  test "bank accounts page shows pending bank connection state", %{conn: conn} do
    admin = admin_fixture()

    {:ok, _requisition} =
      %{id: Ecto.UUID.generate()}
      |> Requisition.changeset_to_persist(
        tenant: admin.member.organization_id,
        actor: admin,
        authorize?: false
      )
      |> Ash.create(tenant: admin.member.organization_id, actor: admin, authorize?: false)

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/firma")

    assert html =~ "Trwa konfiguracja połączenia bankowego."
    assert html =~ "Konto pojawi się na liście"
    assert html =~ "po zakończeniu autoryzacji"
  end

  test "admin changes an employee's role and the employee gains its permissions", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})
    employee_conn = log_in_user(build_conn(), employee)

    assert {:error, {:redirect, _redirect}} = live(employee_conn, ~p"/zarzadzanie/pracownicy")

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/ustawienia/firma")

    view
    |> element("button[phx-click='open_update_role_modal'][phx-value-user_id='#{employee.id}']")
    |> render_click()

    view
    |> form("#update_role_form", %{"user_id" => employee.id, "role" => "admin"})
    |> render_submit()

    assert render(view) =~ "Rola użytkownika została zmieniona."
    assert {:ok, _view, _html} = live(employee_conn, ~p"/zarzadzanie/pracownicy")
  end

  test "an employee saves their contact details on their organization member", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    Core.update_member_profile!(
      employee.member,
      %{correspondence_address: "skr. poczt. 7, 30-001 Kraków"},
      scope: %Scope{actor: employee, tenant: admin.member.organization_id}
    )

    {:ok, lv, html} = live(log_in_user(conn, employee), ~p"/ustawienia/profil")
    assert html =~ "skr. poczt. 7, 30-001 Kraków"
    render_click(lv, "toggle_editing_profile_contact")

    lv
    |> form("form[phx-submit=save_profile_contact]", %{
      "user" => %{
        "phone" => "+48 600 100 200",
        "residence_address" => "ul. Grodzka 5, 31-006 Kraków",
        "is_same_correspondence_address" => "true"
      }
    })
    |> render_submit()

    member = Core.load_member(employee).member
    assert member.phone == "+48 600 100 200"
    assert member.residence_address == "ul. Grodzka 5, 31-006 Kraków"
    assert member.correspondence_address == nil
    assert Core.load_member(admin).member.phone == nil
  end

  test "personal data are saved together or not at all, with the error on the rejected field", %{
    conn: conn
  } do
    user = user_fixture(%{name: "Ada Lovelace"})

    {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/ustawienia/konto")
    render_click(lv, "toggle_editing_account_name")

    render_submit(lv, "save", %{
      "user" => %{"first_name" => "Grace", "last_name" => "Hopper", "birthday" => "1990-13-45"}
    })

    assert has_element?(lv, "#user_birthday[aria-invalid=true]")
    refute has_element?(lv, "#user_first_name[aria-invalid=true]")

    render_submit(lv, "save", %{
      "user" => %{"first_name" => "", "last_name" => "", "birthday" => "1990-05-01"}
    })

    assert has_element?(lv, "#user_first_name[aria-invalid=true]")
    refute has_element?(lv, "#user_birthday[aria-invalid=true]")

    member = Core.load_member(user).member
    assert member.name == "Ada Lovelace"
    assert member.birthday == nil
  end

  test "an employee's name edit lands on their member", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{name: "Ada Lovelace"})

    {:ok, lv, _html} = live(log_in_user(conn, employee), ~p"/ustawienia/konto")
    render_click(lv, "toggle_editing_account_name")

    html =
      render_submit(lv, "save", %{
        "user" => %{"first_name" => "Grace", "last_name" => "Hopper", "birthday" => ""}
      })

    assert html =~ "Cześć, <span class=\"font-bold\">Grace Hopper</span>!"
    assert Core.load_member(employee).member.name == "Grace Hopper"
    assert Core.load_member(admin).member.name != "Grace Hopper"
  end

  test "account deletion modal warns organization owner about deleting the organization", %{
    conn: conn
  } do
    admin = admin_fixture()

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/konto")

    assert html =~ "Usuniemy Twoje konto i wszystkie przypisane do niego dane."
    assert html =~ "Usuniemy też organizacje, których jesteś właścicielem"
  end

  test "account deletion modal names an owned organization other than the current one", %{
    conn: conn
  } do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)

    Core.create_organization!(%{nip: unique_nip(), name: "Firma Pracownika", owner_name: "Ewa"},
      actor: employee
    )

    conn =
      conn
      |> log_in_user(employee)
      |> Plug.Test.init_test_session(%{"organization_id" => admin.member.organization_id})

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/konto")

    assert html =~ "Usuniemy też organizacje, których jesteś właścicielem"
    assert html =~ "Firma Pracownika"
  end

  test "account deletion modal does not warn non-owner about deleting the organization", %{
    conn: conn
  } do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)

    conn = log_in_user(conn, employee)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/konto")

    assert html =~ "Usuniemy Twoje konto i wszystkie przypisane do niego dane."
    refute html =~ "Usuniemy też organizacje"
  end

  test "company settings shows when a connected KSeF certificate is being renewed", %{conn: conn} do
    admin = admin_fixture()

    Ash.Seed.seed!(Credential, %{
      organization_id: admin.member.organization_id,
      status: :refreshing,
      auth_type: :generated_certificate,
      expires_on: Date.add(Date.utc_today(), 7)
    })

    conn = log_in_user(conn, admin)

    assert {:ok, view, _html} = live(conn, ~p"/ustawienia/firma")
    assert has_element?(view, "section", "Trwa odnawianie certyfikatu KSeF")
  end

  defp iban_position(html, iban) do
    case :binary.match(html, iban) do
      {position, _length} -> position
      :nomatch -> flunk("Expected to find IBAN #{iban} in rendered HTML")
    end
  end
end
