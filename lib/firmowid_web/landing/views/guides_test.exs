defmodule FirmowidWeb.Landing.Views.GuidesTest do
  use FirmowidWeb.ConnCase, async: true

  alias FirmowidWeb.Landing.Utilities.Guides

  defp title(html) do
    [_, title] = Regex.run(~r/<title[^>]*>\s*(.*?)\s*<\/title>/s, html)
    title
  end

  test "the index shows the heading from index.yml and lists every guide", %{conn: conn} do
    html = conn |> get(~p"/poradnik") |> html_response(200)

    assert html =~ Guides.index_page().heading
    assert html =~ ~s("@type":"ItemList")
    for guide <- Guides.all(), do: assert(html =~ ~p"/poradnik/#{guide.slug}")
  end

  test "a guide is in main and has one sign-up box", %{conn: conn} do
    html = conn |> get(~p"/poradnik/tryb-offline-ksef") |> html_response(200)

    assert html =~ "<main>"
    assert length(Regex.scan(~r/data-landing-cta="guide_mid_register"/, html)) == 1
    assert html =~ ~s("@type":"FAQPage")
  end

  test "a guide with only sources after one section has no box", %{conn: conn} do
    html = conn |> get(~p"/poradnik/aplikacja-mobilna-ksef") |> html_response(200)

    refute html =~ "guide_mid_register"
  end

  test "a long title drops the brand suffix and a short one keeps it", %{conn: conn} do
    long = conn |> get(~p"/poradnik/tryb-offline-ksef") |> html_response(200) |> title()

    short =
      build_conn() |> get(~p"/poradnik/korekta-faktury-ksef") |> html_response(200) |> title()

    refute long =~ "· Firmowid"
    assert short == "Korekta faktury w KSeF · Firmowid"
  end

  test "an unknown guide is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/poradnik/nie-ma-takiego") end
  end
end
