defmodule FirmowidWeb.Auth.Views.BlockedPagesTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Core

  test "organization owner without a plan signs in to the expired subscription page", %{
    conn: conn
  } do
    admin = admin_fixture()
    expire_subscription!(admin.member.organization_id)

    conn = sign_in(conn, admin)

    assert redirected_to(conn) =~ ~p"/abonament-wygasl"
    refute get_session(conn, :user_token)

    {:ok, _view, html} = live(recycle(conn), redirected_to(conn))
    assert html =~ "Abonament wygasł"
    assert html =~ "Test Organization"
    assert html =~ "Skontaktuj się w sprawie abonamentu"
  end

  test "member of an organization without a plan signs in to the disabled account page", %{
    conn: conn
  } do
    admin = admin_fixture()
    member = user_in_org_fixture(admin.member.organization_id)
    expire_subscription!(admin.member.organization_id)

    conn = sign_in(conn, member)

    assert redirected_to(conn) == ~p"/konto-wylaczone"
    refute get_session(conn, :user_token)
  end

  test "an existing session stops authenticating once the organization has no plan", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)
    expire_subscription!(admin.member.organization_id)

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/czasosledz")
    assert to == ~p"/zaloguj"
  end

  test "a signed-in user is sent away from the blocked pages", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/czasosledz"}}} = live(conn, ~p"/konto-wylaczone")
    assert {:error, {:redirect, %{to: "/czasosledz"}}} = live(conn, ~p"/abonament-wygasl")
  end

  defp sign_in(conn, user) do
    {:ok, lv, _html} = live(conn, ~p"/zaloguj")

    lv
    |> form("#login_form",
      user: %{email: user.email, password: valid_user_password()},
      remember_me: false
    )
    |> submit_form(conn)
  end

  defp expire_subscription!(organization_id) do
    organization = Core.get_organization!(organization_id, authorize?: false)

    Core.update_organization_billing_plan!(organization, %{billing_plan: :no_plan}, authorize?: false)
  end
end
