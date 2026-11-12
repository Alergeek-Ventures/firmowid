defmodule FirmowidWeb.Infrastructure.Controllers.FallbackTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  test "an employee opening the payroll CSV export is refused", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    conn =
      conn
      |> log_in_user(employee)
      |> get(~p"/czasosledz/projekty/csv?miesiac=1&rok=2026")

    assert response(conn, 401) =~ "Unauthorized"
  end
end
