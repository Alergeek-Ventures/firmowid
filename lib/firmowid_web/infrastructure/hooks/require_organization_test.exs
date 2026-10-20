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
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    Core.archive_member!(employee.member, scope: scope_for(admin))

    conn = log_in_user(conn, employee)

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/czasosledz")
    assert to == OrganizationNavigation.onboarding_path()
  end

  test "an archived member is sent to onboarding on protected controller routes", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    Core.archive_member!(employee.member, scope: scope_for(admin))

    conn =
      conn
      |> log_in_user(employee)
      |> get(~p"/czasosledz/projekty/csv")

    assert redirected_to(conn) == OrganizationNavigation.onboarding_path()
  end

  defp scope_for(admin), do: %Scope{actor: admin, tenant: admin.organization_id}
end
