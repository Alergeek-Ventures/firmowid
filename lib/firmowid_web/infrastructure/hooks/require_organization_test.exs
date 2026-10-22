defmodule FirmowidWeb.Infrastructure.Hooks.RequireOrganizationTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation

  test "an archived member is sent to onboarding on protected live routes", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    Core.archive_member!(employee.member, scope: scope_for(admin))

    conn = log_in_user(conn, employee)

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/czasosledz")
    assert to == OrganizationNavigation.onboarding_path()
  end

  test "an archived member is sent to onboarding on protected controller routes", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    Core.archive_member!(employee.member, scope: scope_for(admin))

    conn =
      conn
      |> log_in_user(employee)
      |> get(~p"/czasosledz/projekty/csv")

    assert redirected_to(conn) == OrganizationNavigation.onboarding_path()
  end

  test "an account without a member is sent to onboarding", %{conn: conn} do
    user = Core.register_with_password!(valid_user_attributes(), authorize?: false, actor: %{})

    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/czasosledz")
    assert to == OrganizationNavigation.onboarding_path()
  end

  test "an admin cannot open another organization's employee", %{conn: conn} do
    admin = admin_fixture()
    other_employee = user_in_org_fixture(admin_fixture().member.organization_id)

    conn = log_in_user(conn, admin)

    assert {:error, {:live_redirect, %{to: "/zarzadzanie/pracownicy" <> _}}} =
             live(conn, ~p"/zarzadzanie/pracownicy/#{other_employee.id}")
  end

  test "an archived member joining another organization by invitation works in it", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)
    Core.archive_member!(employee.member, scope: scope_for(admin))

    other_admin = admin_fixture()
    invite = Core.create_invite!(%{issued_by_id: other_admin.id}, scope: scope_for(other_admin))

    {:ok, lv, _html} =
      conn |> log_in_user(employee) |> live(OrganizationNavigation.onboarding_path())

    assert {:error, {:redirect, %{to: "/"}}} =
             lv
             |> form("#join_form", %{code: invite.invite_code, name: "Sable Orin"})
             |> render_submit()

    assert Core.load_member(employee).member.organization_id == other_admin.member.organization_id
    assert {:ok, _lv, _html} = conn |> log_in_user(employee) |> live(~p"/czasosledz")
  end

  defp scope_for(admin), do: %Scope{actor: admin, tenant: admin.member.organization_id}
end
