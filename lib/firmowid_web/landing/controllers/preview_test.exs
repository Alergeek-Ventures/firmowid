defmodule FirmowidWeb.Landing.Controllers.PreviewTest do
  use FirmowidWeb.ConnCase, async: true

  alias FirmowidWeb.Core.Endpoint

  test "serves the preview page and keeps it out of search indexes", %{conn: conn} do
    conn = get(conn, ~p"/landing")

    assert html_response(conn, 200) =~ "dopóki go nie"
    assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
  end

  test "serves the Bonobo case study and keeps it out of search indexes", %{conn: conn} do
    conn = get(conn, ~p"/landing/bonobo")

    assert html_response(conn, 200) =~ "Bonobo"

    assert html_response(conn, 200) =~
             Endpoint.static_path("/landing/case-study.css")

    assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
  end

  test "describes the company and the app in valid structured data", %{conn: conn} do
    html = conn |> get(~p"/landing") |> html_response(200)

    types =
      ~r{<script type="application/ld\+json">(.*?)</script>}s
      |> Regex.scan(html, capture: :all_but_first)
      |> Enum.flat_map(fn [json] ->
        data = Jason.decode!(json)
        Enum.map(data["@graph"] || [data], & &1["@type"])
      end)

    assert "FAQPage" in types
    assert "Organization" in types
    assert "WebApplication" in types
  end

  test "links the stylesheet and script through the static path helper", %{conn: conn} do
    html = conn |> get(~p"/landing") |> html_response(200)

    assert html =~ Endpoint.static_path("/landing/styles.css")
    assert html =~ Endpoint.static_path("/landing/app.js")
  end
end
