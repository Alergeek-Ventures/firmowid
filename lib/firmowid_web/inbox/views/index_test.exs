defmodule FirmowidWeb.Inbox.Views.IndexTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Scope
  alias Firmowid.Timetracker

  test "an admin without KSeF lands on the inbox, which leads to the KSeF settings", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    assert {:error, {:live_redirect, %{to: "/skrzynka"}}} = live(conn, ~p"/fakturowanie")

    {:ok, view, _html} = live(conn, ~p"/skrzynka")
    assert has_element?(view, "#item-ksef-disconnected", "nie wystawisz faktur sprzedażowych")
    assert has_element?(view, ~s(#item-ksef-disconnected a[href="/ustawienia/ksef"]))
  end

  test "a pending leave request leads the admin to the employee's leaves", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{name: "Jan Kowalski"})

    request =
      Timetracker.create_leave_request!(
        %{
          starts_on: Date.add(Date.utc_today(), 10),
          ends_on: Date.add(Date.utc_today(), 12),
          reason: :rest
        },
        scope: %Scope{actor: employee, tenant: employee.member.organization_id}
      )

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/skrzynka")

    assert {:ok, leaves_view, _html} =
             view
             |> element("#item-leave-#{request.id} a")
             |> render_click()
             |> follow_redirect(conn |> recycle() |> log_in_user(admin))

    assert render(leaves_view) =~ "Jan Kowalski"
  end
end
