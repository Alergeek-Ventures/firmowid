defmodule FirmowidWeb.Settings.Views.IndexTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Scope

  test "bank accounts are sorted by IBAN and keep order after rename", %{conn: conn} do
    admin = admin_fixture()
    scope = %Scope{actor: admin, tenant: admin.organization_id}

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

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/konta-bankowe")

    assert iban_position(html, "PL44 1140 2004 0000 3002 0135 5361") <
             iban_position(html, "PL44 1140 2004 0000 3002 0135 5362")

    assert iban_position(html, "PL44 1140 2004 0000 3002 0135 5362") <
             iban_position(html, "PL44 1140 2004 0000 3002 0135 5363")

    assert {:ok, _updated} =
             Finances.update_bank_account(account_1, %{name: "ZZZ renamed"}, scope: scope)

    assert {:ok, _view, html_after_rename} = live(conn, ~p"/ustawienia/konta-bankowe")

    assert iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5361") <
             iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5362")

    assert iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5362") <
             iban_position(html_after_rename, "PL44 1140 2004 0000 3002 0135 5363")

    assert {:ok, _updated} =
             Finances.update_bank_account(account_3, %{name: "AAA renamed"}, scope: scope)

    assert {:ok, _view, html_after_second_rename} = live(conn, ~p"/ustawienia/konta-bankowe")

    assert iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5361") <
             iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5362")

    assert iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5362") <
             iban_position(html_after_second_rename, "PL44 1140 2004 0000 3002 0135 5363")
  end

  test "bank accounts page shows pending bank connection state", %{conn: conn} do
    admin = admin_fixture()

    {:ok, _requisition} =
      Requisition
      |> Ash.Changeset.for_create(:persist, %{id: Ecto.UUID.generate()},
        tenant: admin.organization_id,
        actor: admin,
        authorize?: false
      )
      |> Ash.create(tenant: admin.organization_id, actor: admin, authorize?: false)

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/konta-bankowe")

    assert html =~ "Trwa konfiguracja połączenia bankowego."
    assert html =~ "Konto pojawi się na liście"
    assert html =~ "po zakończeniu autoryzacji"
  end

  test "account deletion modal warns organization owner about deleting the organization", %{
    conn: conn
  } do
    admin = admin_fixture()

    conn = log_in_user(conn, admin)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/konto")

    assert html =~ "Usuniemy Twoje konto i wszystkie przypisane do niego dane."
    assert html =~ "Usuniemy też całą organizację i wszystkie jej dane."
  end

  test "account deletion modal does not warn non-owner about deleting the organization", %{
    conn: conn
  } do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id)

    conn = log_in_user(conn, employee)

    assert {:ok, _view, html} = live(conn, ~p"/ustawienia/konto")

    assert html =~ "Usuniemy Twoje konto i wszystkie przypisane do niego dane."
    refute html =~ "Usuniemy też całą organizację i wszystkie jej dane."
  end

  defp iban_position(html, iban) do
    case :binary.match(html, iban) do
      {position, _length} -> position
      :nomatch -> flunk("Expected to find IBAN #{iban} in rendered HTML")
    end
  end
end
