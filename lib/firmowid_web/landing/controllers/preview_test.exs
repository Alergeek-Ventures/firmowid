defmodule FirmowidWeb.Landing.Controllers.PreviewTest do
  use FirmowidWeb.ConnCase, async: true

  test "serves the preview page and keeps it out of search indexes", %{conn: conn} do
    conn = get(conn, ~p"/landing")

    assert html_response(conn, 200) =~ "Faktury to nie"
    assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
  end
end
