defmodule FirmowidWeb.Landing.Views.IndexTest do
  use FirmowidWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Firmowid"
  end

  test "the open-source page links the guide on self-hosting", %{conn: conn} do
    html = conn |> get(~p"/open-source") |> html_response(200)

    assert html =~ ~s(href="/poradnik/ksef-self-hosted")
  end
end
