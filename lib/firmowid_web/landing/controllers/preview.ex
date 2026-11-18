defmodule FirmowidWeb.Landing.Controllers.Preview do
  @moduledoc """
  Serves the preview of the new home page at `/landing` and its case study
  pages, such as `/landing/bonobo`.

  The pages are self-contained static documents kept in `priv/static/landing`.
  They are excluded from search indexes until they replace the home page.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Core.Endpoint

  @home_path Application.app_dir(:firmowid, "priv/static/landing/index.html")
  @external_resource @home_path
  @home File.read!(@home_path)

  @bonobo_path Application.app_dir(:firmowid, "priv/static/landing/bonobo.html")
  @external_resource @bonobo_path
  @bonobo File.read!(@bonobo_path)

  # The CDN keeps static files for hours, so the pages link to digested copies
  # of their stylesheets and scripts. Each deploy then changes their URLs.
  @assets [
    "/landing/styles.css",
    "/landing/case-study.css",
    "/landing/app.js",
    "/landing/case-study.js"
  ]

  @doc "Returns the preview of the new home page."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params), do: render_page(conn, @home)

  @doc "Returns the Bonobo case study."
  @spec bonobo(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def bonobo(conn, _params), do: render_page(conn, @bonobo)

  # sobelow_skip ["XSS.HTML"]
  # Each page is a file read at compile time and the only substitutions are
  # static paths of our own assets; nothing comes from the request.
  defp render_page(conn, page) do
    page =
      Enum.reduce(@assets, page, fn path, page ->
        String.replace(page, ~s("#{path}"), ~s("#{Endpoint.static_path(path)}"))
      end)

    conn
    |> put_resp_header("x-robots-tag", "noindex")
    |> html(page)
  end
end
