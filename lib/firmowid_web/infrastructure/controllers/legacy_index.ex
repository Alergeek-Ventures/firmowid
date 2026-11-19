defmodule FirmowidWeb.Infrastructure.Controllers.LegacyIndex do
  @moduledoc """
  Redirects legacy URLs: `/index.html` to the root path and
  `/funkcje/faktury-ksef` to `/funkcje/fakturowanie`.
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
  Permanently redirects `/funkcje/faktury-ksef` to `/funkcje/fakturowanie`.
  """
  def invoicing(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/funkcje/fakturowanie")
  end
end
