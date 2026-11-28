defmodule FirmowidWeb.Landing.Controllers.PreviewTest do
  use FirmowidWeb.ConnCase, async: false

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

  test "serves the Bonobo case study to search engines", %{conn: conn} do
    conn = get(conn, ~p"/historie/bonobo")
    html = html_response(conn, 200)

    assert html =~ "Bonobo"
    assert html =~ Endpoint.static_path("/landing/case-study.css")
    assert html =~ ~s(<link rel="canonical" href="https://firmowid.pl/historie/bonobo">)
    refute html =~ "noindex"
    assert get_resp_header(conn, "x-robots-tag") == []

    assert build_conn() |> get(~p"/sitemap.xml") |> response(200) =~
             "/historie/bonobo</loc>"
  end

  test "redirects the former case study address", %{conn: conn} do
    conn = get(conn, "/landing/bonobo")

    assert redirected_to(conn, 301) == ~p"/historie/bonobo"
  end

  test "serves the KSeF pricing page to search engines, in Polish only", %{conn: conn} do
    conn = get(conn, ~p"/ksef")
    html = html_response(conn, 200)

    assert html =~ "Faktury KSeF bez limitu."
    assert html =~ ~s(<link rel="canonical" href="https://firmowid.pl/ksef">)
    refute html =~ "/funkcje/fakturowanie"
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

  test "gives each page its own link preview image", %{conn: conn} do
    for {path, image} <- [{"/", "home"}, {"/ksef", "ksef"}, {"/historie/bonobo", "bonobo"}] do
      html = conn |> get(path) |> html_response(200)

      assert html =~ ~s(<meta property="og:image" content="https://firmowid.pl/images/og/#{image}.png">)
    end
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

  describe "analytics" do
    @ctas %{
      "navbar_login" => ["Zaloguj się"],
      "navbar_trial" => ["Wypróbuj"],
      "hero_trial" => ["Policz 3 projekty za darmo"],
      "pricing_free" => ["Załóż darmowe konto"],
      "pricing_mini" => ["Wypróbuj za darmo"],
      "pricing_przedsiebiorca" => ["Wypróbuj za darmo"],
      "pricing_firma" => ["Wypróbuj za darmo"],
      "final_trial" => ["Zacznij za darmo", "Zacznij za darmo"],
      "demo_booking" => ["Umów 15-minutową rozmowę"],
      "case_study_request" => ["Wyślijcie mi case study"],
      "github" => ["GitHub", "open source", "Zobacz na GitHubie"],
      "open_source" => ["Więcej o open source"]
    }

    test "names every call to action for the click event", %{conn: conn} do
      page = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

      for {cta, labels} <- @ctas do
        found =
          page
          |> LazyHTML.query(~s([data-landing-page="true"] a[data-landing-cta="#{cta}"]))
          |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

        assert found == labels, "#{cta}: #{inspect(found)}"
      end

      assert [_card] =
               page
               |> LazyHTML.query(~s(a[data-landing-cta="case_bonobo"][href="/historie/bonobo"]))
               |> Enum.to_list()

      # Every link to the registration and sign-in pages is a named call to action.
      for href <- ["/zarejestruj", "/zaloguj"] do
        assert [] ==
                 page
                 |> LazyHTML.query(~s|a[href="#{href}"]:not([data-landing-cta])|)
                 |> Enum.to_list()
      end
    end

    defp put_posthog(enabled?) do
      settings = Application.get_env(:firmowid, :frontend_observability, [])

      Application.put_env(
        :firmowid,
        :frontend_observability,
        Keyword.merge(settings, posthog_enabled: enabled?, posthog_api_key: "phc_example")
      )

      on_exit(fn -> Application.put_env(:firmowid, :frontend_observability, settings) end)
    end

    defp telemetry_scripts(conn) do
      html = conn |> get(~p"/") |> html_response(200)
      refute html =~ "__TELEMETRY_SCRIPT__"

      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(body > script[data-telemetry-config="true"]))
      |> Enum.to_list()
    end

    defp waiting_telemetry(conn) do
      Regex.run(
        ~r{<template id="telemetry-script">(<script[^>]*></script>)</template>},
        conn |> get(~p"/") |> html_response(200),
        capture: :all_but_first
      )
    end

    test "loads the telemetry script only for a visitor who accepted analytics", %{conn: conn} do
      put_posthog(true)

      assert [] == telemetry_scripts(conn)
      assert [] == telemetry_scripts(put_req_cookie(conn, "cookie_consent", "rejected"))
      assert [script] = telemetry_scripts(put_req_cookie(conn, "cookie_consent", "accepted"))

      assert LazyHTML.attribute(script, "src") == [
               Endpoint.static_path("/assets/landing_preview.js")
             ]

      assert LazyHTML.attribute(script, "data-public-marketing") == ["true"]
      assert LazyHTML.attribute(script, "data-posthog-enabled") == ["true"]
      assert LazyHTML.attribute(script, "data-posthog-api-key") == ["phc_example"]
      assert LazyHTML.attribute(script, "data-current-user-id") == [""]
    end

    test "loads no telemetry script when analytics is switched off", %{conn: conn} do
      put_posthog(false)

      assert [] == telemetry_scripts(put_req_cookie(conn, "cookie_consent", "accepted"))
    end

    test "keeps the script inert until a visitor without a choice accepts", %{conn: conn} do
      put_posthog(true)

      assert [script] = waiting_telemetry(conn)
      assert script =~ Endpoint.static_path("/assets/landing_preview.js")
      assert script =~ ~s(data-posthog-api-key="phc_example")

      refute waiting_telemetry(put_req_cookie(conn, "cookie_consent", "accepted"))
      refute waiting_telemetry(put_req_cookie(conn, "cookie_consent", "rejected"))

      put_posthog(false)
      refute waiting_telemetry(conn)
    end

    for {name, path} <- [{"home page", "/"}, {"KSeF page", "/ksef"}] do
      test "shows the cookie banner on the #{name}, hidden until the script reveals it", %{
        conn: conn
      } do
        page = conn |> get(unquote(path)) |> html_response(200) |> LazyHTML.from_document()

        assert [_banner] = page |> LazyHTML.query("#consent[hidden]") |> Enum.to_list()

        assert ["rejected", "accepted"] ==
                 page |> LazyHTML.query("#consent button") |> LazyHTML.attribute("data-consent")

        assert [_link] =
                 page
                 |> LazyHTML.query(~s|#consent a[href="/polityka-prywatnosci"]|)
                 |> Enum.to_list()
      end
    end

    test "names the calls to action of the KSeF page", %{conn: conn} do
      page = conn |> get(~p"/ksef") |> html_response(200) |> LazyHTML.from_document()

      expected = %{
        "navbar_login" => 1,
        "navbar_trial" => 1,
        "hero_trial" => 1,
        "pricing_free" => 1,
        "pricing_mini" => 1,
        "pricing_przedsiebiorca" => 1,
        "pricing_firma" => 1,
        "final_trial" => 1,
        "demo_booking" => 2,
        "github" => 2
      }

      found =
        page
        |> LazyHTML.query(~s([data-landing-page="true"] a[data-landing-cta]))
        |> LazyHTML.attribute("data-landing-cta")
        |> Enum.frequencies()

      assert found == expected
      assert Enum.all?(Map.keys(expected), &(&1 in Map.keys(@ctas)))

      for href <- ["/zarejestruj", "/zaloguj"] do
        assert [] ==
                 page
                 |> LazyHTML.query(~s|a[href="#{href}"]:not([data-landing-cta])|)
                 |> Enum.to_list()
      end
    end

    test "loads the telemetry script on the KSeF page as on the home page", %{conn: conn} do
      put_posthog(true)
      page = fn conn -> conn |> get(~p"/ksef") |> html_response(200) end

      assert page.(conn) =~ ~s(<template id="telemetry-script"><script)
      refute page.(conn) =~ "__TELEMETRY_SCRIPT__"

      accepted = page.(put_req_cookie(conn, "cookie_consent", "accepted"))
      assert accepted =~ Endpoint.static_path("/assets/landing_preview.js")
      refute accepted =~ "<template"

      refute page.(put_req_cookie(conn, "cookie_consent", "rejected")) =~ "landing_preview"
    end

    test "the case study page has no placeholder either", %{conn: conn} do
      refute conn |> get(~p"/historie/bonobo") |> html_response(200) =~ "__TELEMETRY_SCRIPT__"
    end
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
        |> get(~p"/historie/bonobo")
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
