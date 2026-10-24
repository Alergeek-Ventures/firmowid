defmodule FirmowidWeb.Infrastructure.Controllers.Sitemap do
  @moduledoc """
  Serves XML sitemap for public pages.
  """
  use FirmowidWeb, :controller

  alias FirmowidWeb.Core.Endpoint

  @public_paths ["/", "/cennik", "/funkcje", "/faq", "/polityka-prywatnosci", "/regulamin"]

  @doc """
  Returns sitemap.xml containing canonical public URLs.
  """
  # sobelow_skip ["XSS.SendResp"]
  # This XML contains only fixed public paths and the configured endpoint URL,
  # never request input; it is served as application/xml.
  def index(conn, _params) do
    urls =
      Enum.map_join(@public_paths, "\n", fn path ->
        """
        <url>
          <loc>#{Endpoint.url()}#{path}</loc>
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
