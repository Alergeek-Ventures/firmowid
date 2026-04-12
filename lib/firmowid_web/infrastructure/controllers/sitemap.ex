defmodule FirmowidWeb.Infrastructure.Controllers.Sitemap do
  @moduledoc """
  Serves XML sitemap for public pages.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Core.Endpoint

  @public_paths ["/", "/polityka-prywatnosci", "/regulamin"]

  @doc """
  Returns sitemap.xml containing canonical public URLs.
  """
  def index(conn, _params) do
    now = Date.to_iso8601(Date.utc_today())

    urls =
      Enum.map_join(@public_paths, "\n", fn path ->
        """
        <url>
          <loc>#{Endpoint.url()}#{path}</loc>
          <lastmod>#{now}</lastmod>
        </url>
        """
      end)

    body =
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{urls}
      </urlset>
      """

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, body)
  end
end
