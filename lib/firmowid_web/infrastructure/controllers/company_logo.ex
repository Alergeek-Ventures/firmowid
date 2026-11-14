defmodule FirmowidWeb.Infrastructure.Controllers.CompanyLogo do
  @moduledoc """
  Serves the icon of a company's website, looked up by its domain in Google's
  favicon service, or 404 when the site has none worth showing.

  The server asks Google, not the browser: Google learns a domain, never which
  member or organization works with that company, and the page needs no new
  image source in its content security policy.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Invoicing.Services.CounterpartyWebsite

  # A smaller icon blurs once stretched, so the type icon stays instead.
  @min_width 32

  @doc "Sends the PNG icon of the company's website `domain`, or 404."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"domain" => domain}) do
    with true <- CounterpartyWebsite.valid_domain?(domain),
         {:ok, png} <- fetch_icon(domain) do
      send_icon(conn, png)
    else
      _missing ->
        conn
        |> put_resp_header("cache-control", "private, max-age=86400")
        |> send_resp(404, "")
    end
  end

  # Google answers 404 with a generic globe when it knows no icon for the site. Any
  # other failure crashes at once: retrying would hold up the page's image request.
  defp fetch_icon(domain) do
    case Req.get!("https://www.google.com/s2/favicons",
           params: [domain: domain, sz: 64],
           retry: false
         ) do
      %{
        status: 200,
        body: <<0x89, "PNG\r\n", 0x1A, "\n", _::32, "IHDR", width::32, _::binary>> = png
      }
      when width >= @min_width ->
        {:ok, png}

      %{status: status} when status in [200, 404] ->
        :error
    end
  end

  # sobelow_skip ["XSS.SendResp"]
  # PNG bytes checked by their signature, sent as image/png with nosniff.
  # A site changes its icon rarely, so browsers keep it for a week.
  defp send_icon(conn, png) do
    conn
    |> put_resp_content_type("image/png", nil)
    |> put_resp_header("cache-control", "private, max-age=604800, no-transform")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, png)
  end
end
