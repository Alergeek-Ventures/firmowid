defmodule FirmowidWeb.Landing.Controllers.Preview do
  @moduledoc """
  Serves the preview of the new home page at `/landing`.

  The page is a self-contained static document kept in `priv/static/landing`.
  It is not linked from anywhere and is excluded from search indexes.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Core.Endpoint

  @page_path Application.app_dir(:firmowid, "priv/static/landing/index.html")
  @external_resource @page_path
  @page File.read!(@page_path)

  # The CDN keeps static files for hours, so the page links to digested copies
  # of its stylesheet and script. Each deploy then changes their URLs.
  @assets ["/landing/styles.css", "/landing/app.js"]

  @doc "Returns the preview page with a header that keeps it out of search indexes."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  # sobelow_skip ["XSS.HTML"]
  # The page is a file read at compile time and the only substitutions are
  # static paths of our own assets; nothing comes from the request.
  def show(conn, _params) do
    page =
      Enum.reduce(@assets, @page, fn path, page ->
        String.replace(page, ~s("#{path}"), ~s("#{Endpoint.static_path(path)}"))
      end)

    conn
    |> put_resp_header("x-robots-tag", "noindex")
    |> html(page)
  end
end
