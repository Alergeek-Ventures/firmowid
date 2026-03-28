defmodule FirmowidWeb.LandingLiveTest do
  use FirmowidWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Firmowid"
  end
end
