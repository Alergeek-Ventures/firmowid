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

  test "the help index has its own search title and description", %{conn: conn} do
    html = conn |> get(~p"/pomoc") |> html_response(200)
    help = Guides.help_index_page()

    assert html =~ ~r/<title[^>]*>\s*#{Regex.escape(help.title)}\s*<\/title>/
    assert html =~ ~s(<meta name="description" content="#{help.description}")
    assert html =~ "<h1>#{help.heading}</h1>"
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

  test "a feature page signs its quote with the author from the front matter", %{conn: conn} do
    texts = Guides.feature_page()

    bank = conn |> get(~p"/funkcje/bank") |> html_response(200)
    assert bank =~ texts.quote_franek_name
    assert bank =~ ~s(src="/images/team-franek-madej.webp")
    refute bank =~ texts.quote_name

    time = conn |> get(~p"/funkcje/czas-pracy") |> html_response(200)
    assert time =~ texts.quote_name
    refute time =~ texts.quote_franek_name
  end

  test "the time tracking feature page draws a running timer and compares prices", %{conn: conn} do
    html = conn |> get(~p"/funkcje/czas-pracy") |> html_response(200)

    assert html =~ Guides.feature_page().timer_stop
    assert html =~ "--timer-m: 48; --timer-s: 6; --timer-offset: -2886s"
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

  test "the KSeF page replaces the invoicing feature pages", %{conn: conn} do
    assert conn |> get("/funkcje/fakturowanie") |> redirected_to(301) == "/ksef"
    assert build_conn() |> get("/funkcje/faktury-ksef") |> redirected_to(301) == "/ksef"

    features = build_conn() |> get(~p"/funkcje") |> html_response(200)
    sitemap = build_conn() |> get(~p"/sitemap.xml") |> response(200)

    assert features =~ ~s(href="/ksef")
    refute features =~ "/funkcje/fakturowanie"
    refute sitemap =~ "/funkcje/fakturowanie"
    refute sitemap =~ "/funkcje/faktury-ksef"
  end

  test "the team page covers leave requests and replaces /funkcje/urlopy", %{conn: conn} do
    html = conn |> get(~p"/funkcje/zespol") |> html_response(200)

    assert html =~ ~s(id="urlopy-i-nieobecnosci")
    assert html =~ ~s(href="#ile-to-kosztuje")
    assert html =~ ~s(<tr class="firmowid">)
    assert build_conn() |> get("/funkcje/urlopy") |> redirected_to(301) == "/funkcje/zespol"
    refute build_conn() |> get(~p"/sitemap.xml") |> response(200) =~ "/funkcje/urlopy"
  end

  test "the analysis feature page draws the split of 100 zł and compares programs", %{conn: conn} do
    html = conn |> get(~p"/funkcje/analiza") |> html_response(200)

    assert html =~ Guides.feature_page().split_headline
    assert html =~ "Wynagrodzenia i ZUS"
    assert html =~ "width: 38%; background: var(--color-rust-800)"
    assert html =~ ~s(<tr class="firmowid">)
    assert html =~ ~s(href="#jak-liczy-analiza")
  end

  test "the AI page covers the assistant and replaces /funkcje/asystent", %{conn: conn} do
    html = conn |> get(~p"/funkcje/claude-chatgpt-mcp") |> html_response(200)

    assert html =~ ~s(id="asystent-ai-w-aplikacji")
    assert html =~ ~s(href="#zatwierdzanie-zmian")
    assert html =~ ~s(<tr class="firmowid">)

    assert build_conn() |> get("/funkcje/asystent") |> redirected_to(301) ==
             "/funkcje/claude-chatgpt-mcp"

    refute build_conn() |> get(~p"/sitemap.xml") |> response(200) =~ "/funkcje/asystent"
  end

  test "the time tracking feature page replaces /funkcje/projekty", %{conn: conn} do
    assert conn |> get("/funkcje/projekty") |> redirected_to(301) == "/funkcje/czas-pracy"

    html = build_conn() |> get(~p"/funkcje/czas-pracy") |> html_response(200)
    sitemap = build_conn() |> get(~p"/sitemap.xml") |> response(200)

    assert html =~ ~s(id="projekty")
    assert html =~ ~s(href="#projekty")
    refute sitemap =~ "/funkcje/projekty"
  end

  test "the merged guide redirects to the free KSeF programs guide", %{conn: conn} do
    assert conn |> get("/poradnik/program-do-faktur-bez-abonamentu") |> redirected_to(301) ==
             "/poradnik/darmowe-programy-ksef"

    html = build_conn() |> get(~p"/poradnik/darmowe-programy-ksef") |> html_response(200)
    sitemap = build_conn() |> get(~p"/sitemap.xml") |> response(200)

    assert html =~ "Plan darmowy czy okres próbny"
    refute sitemap =~ "/poradnik/program-do-faktur-bez-abonamentu"
  end

  test "two merged guides redirect to the ministry tools guide", %{conn: conn} do
    target = "/poradnik/ksef-w-banku-aplikacja-mf-czy-program"

    assert conn |> get("/poradnik/czy-trzeba-kupowac-program-do-ksef") |> redirected_to(301) ==
             target

    assert build_conn() |> get("/poradnik/aplikacja-mobilna-ksef") |> redirected_to(301) == target

    html = build_conn() |> get(target) |> html_response(200)
    sitemap = build_conn() |> get(~p"/sitemap.xml") |> response(200)

    assert html =~ "Aplikacja mobilna KSeF"
    refute sitemap =~ "/poradnik/aplikacja-mobilna-ksef"
    refute sitemap =~ "/poradnik/czy-trzeba-kupowac-program-do-ksef"
  end

  test "an unknown guide is not found", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/poradnik/nie-ma-takiego") end
  end
end
