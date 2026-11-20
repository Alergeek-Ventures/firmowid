defmodule FirmowidWeb.Infrastructure.Controllers.LegacyIndex do
  @moduledoc """
  Redirects legacy URLs: `/index.html` to the root path and
  the former invoicing feature pages to `/ksef`.
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

  @doc """
  Permanently redirects `/funkcje/faktury-ksef` and `/funkcje/fakturowanie` to `/ksef`.
  """
  def invoicing(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/ksef")
  end
end
