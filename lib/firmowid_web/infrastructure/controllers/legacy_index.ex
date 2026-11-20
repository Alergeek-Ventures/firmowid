defmodule FirmowidWeb.Infrastructure.Controllers.LegacyIndex do
  @moduledoc """
  Redirects legacy URLs: `/index.html` to the root path, the former invoicing
  feature pages to `/ksef` and `/funkcje/urlopy` to `/funkcje/zespol`.
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

  @doc """
  Permanently redirects `/funkcje/urlopy` to the team page, which covers leave requests.
  """
  def leave(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/funkcje/zespol")
  end
end
