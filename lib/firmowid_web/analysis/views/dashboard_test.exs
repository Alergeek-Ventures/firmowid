defmodule FirmowidWeb.Analysis.Views.DashboardTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  test "ignores unknown tag filter keys without crashing", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    assert {:ok, _view, _html} =
             live(
               conn,
               ~p"/analiza?month=#{Date.to_iso8601(Date.beginning_of_month(Date.utc_today()))}&tags=company,foo,project"
             )
  end
end
