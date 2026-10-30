defmodule FirmowidWeb.Infrastructure.Controllers.Sitemap do
  @moduledoc """
  Serves XML sitemap for public pages.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Landing.Utilities.Guides

  @public_paths [
    "/",
    "/cennik",
    "/funkcje",
    "/faq",
    "/open-source",
    "/poradnik",
    "/polityka-prywatnosci",
    "/regulamin"
  ]

  @doc """
  Returns sitemap.xml containing canonical public URLs.
  """
  # sobelow_skip ["XSS.SendResp"]
  # This XML contains only fixed public paths, compiled guide slugs and dates, and
  # the configured endpoint URL, never request input; it is served as application/xml.
  def index(conn, _params) do
    entries =
      Enum.map(@public_paths, &{&1, nil}) ++
        Enum.map(Guides.all(), &{"/poradnik/#{&1.slug}", &1.updated})

    urls =
      Enum.map_join(entries, "\n", fn {path, lastmod} ->
        """
        <url>
          <loc>#{Endpoint.url()}#{path}</loc>#{lastmod && "\n  <lastmod>#{Date.to_iso8601(lastmod)}</lastmod>"}
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
