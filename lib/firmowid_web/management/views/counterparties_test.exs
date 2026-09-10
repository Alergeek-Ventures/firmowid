defmodule FirmowidWeb.Management.Views.CounterpartiesTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Scope

  test "admin can create, edit, archive and restore a counterparty", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)
    counterparty_email = unique_user_email()

    {:ok, new_lv, new_html} = live(conn, ~p"/zarzadzanie/kontrahenci/dodaj")

    assert new_html =~ "Nowy kontrahent"

    new_lv
    |> form("form[phx-submit='save'][phx-change='validate']", %{
      "counterparty" => %{
        "type" => "company",
        "display_name" => "Acme",
        "tax_id" => "5261040828",
        "full_name" => "Acme Sp. z o.o.",
        "country" => "PL",
        "address" => "Prosta 1\n00-001 Warszawa",
        "email" => counterparty_email,
        "phone" => "+48123123123",
        "description" => "Pierwszy kontakt"
      }
    })
    |> render_submit()

    counterparty = get_counterparty_by_email!(admin, counterparty_email)

    assert_redirect(new_lv, ~p"/zarzadzanie/kontrahenci/#{counterparty.id}")

    {:ok, _show_lv, show_html} = live(conn, ~p"/zarzadzanie/kontrahenci/#{counterparty.id}")

    assert show_html =~ "Acme"
    assert show_html =~ "Archiwizuj"

    {:ok, edit_lv, edit_html} = live(conn, ~p"/zarzadzanie/kontrahenci/#{counterparty.id}/edycja")

    assert edit_html =~ "Edycja kontrahenta"

    edit_lv
    |> form("form[phx-submit='save'][phx-change='validate']", %{
      "counterparty" => %{
        "type" => "company",
        "display_name" => "Acme po edycji",
        "tax_id" => "5261040828",
        "full_name" => "Acme po edycji Sp. z o.o.",
        "country" => "PL",
        "address" => "Prosta 2\n00-002 Warszawa",
        "email" => counterparty_email,
        "phone" => "+48987654321",
        "description" => "Po aktualizacji"
      }
    })
    |> render_submit()

    assert_redirect(edit_lv, ~p"/zarzadzanie/kontrahenci/#{counterparty.id}")

    {:ok, show_lv, updated_show_html} =
      live(conn, ~p"/zarzadzanie/kontrahenci/#{counterparty.id}")

    assert updated_show_html =~ "Acme po edycji"
    assert updated_show_html =~ "Po aktualizacji"

    show_lv
    |> element("button", "Archiwizuj")
    |> render_click()

    assert render(show_lv) =~ "zarchiwizowany"
    assert render(show_lv) =~ "Przywróć kontrahenta"

    {:ok, _archive_lv, archive_html} = live(conn, ~p"/zarzadzanie/kontrahenci/archiwum")

    assert archive_html =~ "Acme po edycji"

    {:ok, archive_lv, _archive_html} = live(conn, ~p"/zarzadzanie/kontrahenci/archiwum")

    archive_lv
    |> element("button[phx-click='unarchive_counterparty'][phx-value-id='#{counterparty.id}']")
    |> render_click()

    {:ok, _active_lv, active_html} = live(conn, ~p"/zarzadzanie/kontrahenci")

    assert active_html =~ "Acme po edycji"
  end

  test "new counterparty form validates NIP before fetching data", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/zarzadzanie/kontrahenci/dodaj")

    assert has_element?(view, "label[for='counterparty_tax_id']", "NIP/ID*")
    assert has_element?(view, "button[phx-click='fetch_by_nip']", "Pobierz dane")

    view
    |> element("button[phx-click='fetch_by_nip']")
    |> render_click()

    assert has_element?(view, "#counterparty_tax_id[aria-invalid='true']")
    assert render(view) =~ "NIP jest wymagany"

    view
    |> form("form[phx-submit='save'][phx-change='validate']", %{
      "counterparty" => %{"tax_id" => "123"}
    })
    |> render_change()

    view
    |> element("button[phx-click='fetch_by_nip']")
    |> render_click()

    assert has_element?(view, "#counterparty_tax_id[aria-invalid='true']")
    assert render(view) =~ "musi być poprawnym numerem NIP"
  end

  defp current_scope(admin) do
    %Scope{actor: admin, tenant: admin.organization_id}
  end

  defp get_counterparty_by_email!(admin, email) do
    %{status: :all}
    |> Invoicing.list_counterparties!(scope: current_scope(admin))
    |> Enum.find(&(&1.email == email))
    |> Kernel.||(raise "expected counterparty with email #{inspect(email)} to exist")
  end
end
