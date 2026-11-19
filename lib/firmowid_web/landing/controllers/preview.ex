defmodule FirmowidWeb.Landing.Controllers.Preview do
  @moduledoc """
  Serves the preview of the new home page at `/landing`, its case study pages,
  such as `/landing/bonobo`, and the KSeF pricing page at `/ksef`.

  The pages are self-contained static documents kept in `priv/static/landing`,
  written in Polish. The English and Ukrainian versions are built from them at
  compile time with the replacement lists in `priv/landing/translations`, and the
  page follows the language chosen in the session, as the current home page does.
  The preview pages are excluded from search indexes until they replace the home
  page. The KSeF page is public, indexed and Polish only.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Core.Endpoint

  @dir Application.app_dir(:firmowid, "priv/static/landing")
  @translations_dir Application.app_dir(:firmowid, "priv/landing/translations")
  @files ["index.html", "bonobo.html"]
  @polish_only_files ["ksef.html"]
  @locales ["en", "uk"]

  for file <- @files ++ @polish_only_files, do: @external_resource(Path.join(@dir, file))
  for locale <- @locales, do: @external_resource(Path.join(@translations_dir, "#{locale}.json"))

  # %{file => %{locale => html}}. Each translation is a list of [polish, translated]
  # pairs; longer fragments go first, so a short one never cuts into a longer one.
  translated_pages =
    for file <- @files, into: %{} do
      source = File.read!(Path.join(@dir, file))

      translated =
        for locale <- @locales, into: %{} do
          pairs =
            @translations_dir
            |> Path.join("#{locale}.json")
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!(file)
            |> Enum.sort_by(fn [from, _to] -> -String.length(from) end)

          {locale,
           Enum.reduce(pairs, source, fn [from, to], html ->
             String.replace(html, from, to)
           end)}
        end

      {file, Map.put(translated, "pl", source)}
    end

  polish_only_pages =
    Map.new(@polish_only_files, &{&1, %{"pl" => File.read!(Path.join(@dir, &1))}})

  @pages Map.merge(translated_pages, polish_only_pages)

  # The CDN keeps static files for hours, so the pages link to digested copies
  # of their stylesheets and scripts. Each deploy then changes their URLs.
  @assets [
    "/landing/styles.css",
    "/landing/case-study.css",
    "/landing/ksef.css",
    "/landing/app.js",
    "/landing/case-study.js",
    "/landing/ksef.js"
  ]

  @doc "Returns the preview of the new home page."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params), do: render_page(conn, "index.html")

  @doc "Returns the Bonobo case study."
  @spec bonobo(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def bonobo(conn, _params), do: render_page(conn, "bonobo.html")

  @doc "Returns the KSeF pricing page."
  @spec ksef(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ksef(conn, _params), do: render_page(conn, "ksef.html", index?: true)

  # sobelow_skip ["XSS.HTML"]
  # Each page is built at compile time from our own files. The substitutions are
  # static paths of our own assets and the CSRF token for the language menu;
  # nothing comes from the request.
  defp render_page(conn, file, opts \\ []) do
    versions = Map.fetch!(@pages, file)
    page = Map.get(versions, Gettext.get_locale(Firmowid.Gettext), versions["pl"])

    page =
      @assets
      |> Enum.reduce(page, fn path, page ->
        String.replace(page, ~s("#{path}"), ~s("#{Endpoint.static_path(path)}"))
      end)
      |> String.replace("__CSRF_TOKEN__", get_csrf_token())

    conn = if opts[:index?], do: conn, else: put_resp_header(conn, "x-robots-tag", "noindex")

    html(conn, page)
  end
end
