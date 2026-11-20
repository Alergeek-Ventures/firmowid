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

  test "a guide is in main and has FAQPage data", %{conn: conn} do
    html = conn |> get(~p"/poradnik/tryb-offline-ksef") |> html_response(200)

    assert html =~ "<main>"
    assert html =~ ~s("@type":"FAQPage")
  end

  test "a guide ends with three other guides to read next, its category first", %{conn: conn} do
    {:ok, guide} = Guides.fetch("revolut-wise-program-do-faktur")
    read_next = Guides.read_next(guide)

    assert length(read_next) == 3
    refute guide in read_next
    assert hd(read_next).category == guide.category

    html = conn |> get(guide.path) |> html_response(200)

    assert html =~ Guides.index_page().read_next
    for next <- read_next, do: assert(html =~ ~s(href="#{next.path}"))
  end

  test "a help article has no read-next list", %{conn: conn} do
    html = conn |> get(~p"/pomoc/polaczenie-z-ksef") |> html_response(200)

    refute html =~ ~s(id="read-next")
  end

  test "the bank feature page pairs transfers with invoices and compares prices", %{conn: conn} do
    html = conn |> get(~p"/funkcje/bank") |> html_response(200)

    assert html =~ Guides.feature_page().match_transfer
    assert html =~ "Północny Kod"
    assert html =~ ~s(<tr class="firmowid">)
    assert html =~ ~s(href="#banki-i-waluty")
    assert html =~ ~s(src="/images/landing/banks/pkobp.png")
  end

  test "the time tracking feature page draws a running timer and compares prices", %{conn: conn} do
    html = conn |> get(~p"/funkcje/czas-pracy") |> html_response(200)

    assert html =~ Guides.feature_page().timer_stop
    assert html =~ "--timer-m: 40; --timer-s: 6; --timer-offset: -2406s"
    assert html =~ "TacoOverflow"
    assert html =~ ~s(<tr class="firmowid">)
    assert html =~ ~s(href="#ile-to-kosztuje")
  end

  test "a long title drops the brand suffix and a short one keeps it", %{conn: conn} do
    long = conn |> get(~p"/poradnik/tryb-offline-ksef") |> html_response(200) |> title()

    short =
      build_conn() |> get(~p"/poradnik/korekta-faktury-ksef") |> html_response(200) |> title()

    refute long =~ "· Firmowid"
    assert short == "Korekta faktury w KSeF · Firmowid"
  end

  test "the invoicing feature page replaces /funkcje/faktury-ksef", %{conn: conn} do
    html = conn |> get(~p"/funkcje/fakturowanie") |> html_response(200)
    assert title(html) == "Wystawianie faktur: VAT, korekty i faktury w walutach"

    assert build_conn() |> get("/funkcje/faktury-ksef") |> redirected_to(301) ==
             "/funkcje/fakturowanie"

    features = build_conn() |> get(~p"/funkcje") |> html_response(200)
    sitemap = build_conn() |> get(~p"/sitemap.xml") |> response(200)

    assert features =~ ~s(href="/funkcje/fakturowanie")
    assert sitemap =~ "/funkcje/fakturowanie</loc>"
    refute features =~ "/funkcje/faktury-ksef"
    refute sitemap =~ "/funkcje/faktury-ksef"
  end

  test "an unknown guide is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/poradnik/nie-ma-takiego") end
  end
end
