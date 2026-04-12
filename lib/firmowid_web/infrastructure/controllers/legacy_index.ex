defmodule FirmowidWeb.Infrastructure.Controllers.LegacyIndex do
  @moduledoc """
  Redirects legacy `/index.html` URL to root path.
  """
  use FirmowidWeb, :controller

  @doc """
  Permanently redirects `/index.html` to `/`.
  """
  def index(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/")
  end
end
