defmodule FirmowidWeb.Infrastructure.Hooks.RequireOrganizationTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope

  test "archived user is redirected from protected live routes", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    Core.archive_user!(employee, %{}, scope: scope_for(admin))

    conn = log_in_user(conn, employee)

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/czasosledz")
    assert to == ~p"/konto-wylaczone"
  end

  test "archived user is redirected from protected controller routes", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    Core.archive_user!(employee, %{}, scope: scope_for(admin))

    conn =
      conn
      |> log_in_user(employee)
      |> get(~p"/czasosledz/projekty/csv")

    assert redirected_to(conn) == ~p"/konto-wylaczone"
  end

  test "organization owner with expired subscription is redirected from protected live routes", %{
    conn: conn
  } do
    admin = admin_fixture()
    expire_subscription!(admin.organization_id)

    conn = log_in_user(conn, admin)

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/czasosledz")
    assert to == ~p"/abonament-wygasl"
  end

  test "user who is not archived - gets redirected", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/czasosledz"}}} = live(conn, ~p"/konto-wylaczone")
  end

  defp scope_for(admin), do: %Scope{actor: admin, tenant: admin.organization_id}

  defp expire_subscription!(organization_id) do
    organization = Core.get_organization!(organization_id, authorize?: false)

    Core.update_organization_billing_plan!(organization, %{billing_plan: :no_plan}, authorize?: false)
  end
end
