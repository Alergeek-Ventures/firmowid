defmodule FirmowidWeb.Landing.Controllers.Preview do
  @moduledoc """
  Serves the home page at `/`, its case study pages, such as `/landing/bonobo`,
  and the KSeF pricing page at `/ksef`. `/landing`, the address of the home page
  while it was a preview, redirects to `/`.

  The pages are self-contained static documents kept in `priv/static/landing`,
  written in Polish. The English and Ukrainian versions are built from them at
  compile time with the replacement lists in `priv/landing/translations`, and the
  page follows the language chosen in the session. The case study pages are
  excluded from search indexes. The KSeF page is Polish only.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Core
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Infrastructure.UserAuth

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

  @doc "Returns the home page, or sends a signed-in member to the app."
  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    user = conn.assigns[:current_user]

    if user && Core.load_member(user).member do
      redirect(conn, to: UserAuth.signed_in_path(conn))
    else
      render_page(conn, "index.html")
    end
  end

  @doc "Permanently redirects the former preview address `/landing` to `/`."
  @spec landing(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def landing(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/")
  end

  @doc "Returns the Bonobo case study, excluded from search indexes."
  @spec bonobo(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def bonobo(conn, _params) do
    conn
    |> put_resp_header("x-robots-tag", "noindex")
    |> render_page("bonobo.html")
  end

  @doc "Returns the KSeF pricing page."
  @spec ksef(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ksef(conn, _params), do: render_page(conn, "ksef.html")

  # sobelow_skip ["XSS.HTML"]
  # Each page is built at compile time from our own files. The substitutions are
  # static paths of our own assets and the CSRF token for the language menu;
  # nothing comes from the request.
  defp render_page(conn, file) do
    versions = Map.fetch!(@pages, file)
    page = Map.get(versions, Gettext.get_locale(Firmowid.Gettext), versions["pl"])

    page =
      @assets
      |> Enum.reduce(page, fn path, page ->
        String.replace(page, ~s("#{path}"), ~s("#{Endpoint.static_path(path)}"))
      end)
      |> String.replace("__CSRF_TOKEN__", get_csrf_token())

    html(conn, page)
  end
end
