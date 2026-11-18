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

  test "links the stylesheet and script through the static path helper", %{conn: conn} do
    html = conn |> get(~p"/landing") |> html_response(200)

    assert html =~ Endpoint.static_path("/landing/styles.css")
    assert html =~ Endpoint.static_path("/landing/app.js")
  end

  describe "languages" do
    @translations Application.app_dir(:firmowid, "priv/landing/translations")
    @static Application.app_dir(:firmowid, "priv/static/landing")

    test "follows the language chosen in the session", %{conn: conn} do
      en =
        conn |> init_test_session(%{"locale" => "en"}) |> get(~p"/landing") |> html_response(200)

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
      html = conn |> get(~p"/landing") |> html_response(200)

      assert html =~ ~s(action="/jezyk")
      refute html =~ "__CSRF_TOKEN__"
    end

    test "keeps the FAQ structured data valid in every language", %{conn: conn} do
      for locale <- ["pl", "en", "uk"] do
        html =
          conn
          |> init_test_session(%{"locale" => locale})
          |> get(~p"/landing")
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
