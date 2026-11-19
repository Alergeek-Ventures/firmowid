defmodule FirmowidWeb.Landing.Controllers.PreviewTest do
  use FirmowidWeb.ConnCase, async: true

  alias FirmowidWeb.Core.Endpoint

  test "serves the home page at / and lets search engines index it", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "dopóki go nie"
    assert html =~ ~s(<link rel="canonical" href="https://firmowid.pl/">)
    refute html =~ "noindex"
    assert get_resp_header(conn, "x-robots-tag") == []
  end

  test "sends a signed-in member from / to the app", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert conn |> get(~p"/") |> redirected_to() =~ ~r{^/[a-z]}
  end

  test "redirects the former preview address to the home page", %{conn: conn} do
    conn = get(conn, "/landing")

    assert redirected_to(conn, 301) == ~p"/"
  end

  test "serves the Bonobo case study and keeps it out of search indexes", %{conn: conn} do
    conn = get(conn, ~p"/landing/bonobo")

    assert html_response(conn, 200) =~ "Bonobo"

    assert html_response(conn, 200) =~
             Endpoint.static_path("/landing/case-study.css")

    assert get_resp_header(conn, "x-robots-tag") == ["noindex"]
  end

  test "serves the KSeF pricing page to search engines, in Polish only", %{conn: conn} do
    conn = get(conn, ~p"/ksef")
    html = html_response(conn, 200)

    assert html =~ "Faktury KSeF bez limitu."
    assert html =~ ~s(<link rel="canonical" href="https://firmowid.pl/ksef">)
    assert html =~ ~s(href="/funkcje/fakturowanie")
    assert html =~ Endpoint.static_path("/landing/ksef.css")
    assert html =~ Endpoint.static_path("/landing/ksef.js")
    assert html =~ ~s("@type": "FAQPage")
    assert get_resp_header(conn, "x-robots-tag") == []
    refute html =~ "noindex"

    english =
      build_conn()
      |> init_test_session(%{"locale" => "en"})
      |> get(~p"/ksef")
      |> html_response(200)

    assert english =~ "Faktury KSeF bez limitu."

    assert build_conn() |> get(~p"/sitemap.xml") |> response(200) =~ "/ksef</loc>"
  end

  test "describes the company and the app in valid structured data", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

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

  test "links to the KSeF page and the feature pages", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    for path <- [
          "/ksef",
          "/funkcje/bank",
          "/funkcje/czas-pracy",
          "/funkcje/analiza",
          "/funkcje/claude-chatgpt-mcp"
        ] do
      assert html =~ ~s(href="#{path}")
    end
  end

  test "links the stylesheet and script through the static path helper", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ Endpoint.static_path("/landing/styles.css")
    assert html =~ Endpoint.static_path("/landing/app.js")
  end

  describe "languages" do
    @translations Application.app_dir(:firmowid, "priv/landing/translations")
    @static Application.app_dir(:firmowid, "priv/static/landing")

    test "follows the language chosen in the session", %{conn: conn} do
      en =
        conn |> init_test_session(%{"locale" => "en"}) |> get(~p"/") |> html_response(200)

      uk =
        conn
        |> init_test_session(%{"locale" => "uk"})
        |> get(~p"/landing/bonobo")
        |> html_response(200)

      assert en =~ ~s(<html lang="en">)
      assert en =~ "A project looks profitable until you"
      assert uk =~ ~s(<html lang="uk">)
      assert uk =~ "Bonobo: з"
    end

    test "fills in the CSRF token of the language menu", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(action="/jezyk")
      refute html =~ "__CSRF_TOKEN__"
    end

    test "keeps the FAQ structured data valid in every language", %{conn: conn} do
      for locale <- ["pl", "en", "uk"] do
        html =
          conn
          |> init_test_session(%{"locale" => locale})
          |> get(~p"/")
          |> html_response(200)

        [_, json] = Regex.run(~r{<script type="application/ld\+json">(.*?)</script>}s, html)

        assert %{"@type" => "FAQPage"} = Jason.decode!(json)
      end
    end

    # A changed Polish sentence leaves its translation behind. A few stale
    # fragments only keep that text in Polish, so they do not fail the build;
    # a page whose translations mostly stopped matching does.
    test "most translated fragments are still on the Polish page" do
      for locale <- ["en", "uk"] do
        translations =
          @translations |> Path.join("#{locale}.json") |> File.read!() |> Jason.decode!()

        for {file, pairs} <- translations do
          source = File.read!(Path.join(@static, file))
          missing = for [from, _to] <- pairs, not String.contains?(source, from), do: from

          assert length(missing) <= div(length(pairs), 10),
                 "#{locale}/#{file}: #{length(missing)} fragments are no longer on the page: #{inspect(missing)}"
        end
      end
    end
  end
end
