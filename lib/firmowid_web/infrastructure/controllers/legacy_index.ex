defmodule FirmowidWeb.Infrastructure.Controllers.LegacyIndex do
  @moduledoc """
  Redirects legacy URLs: `/index.html` to the root path, the former invoicing
  feature pages to `/ksef`, `/funkcje/urlopy` to `/funkcje/zespol`,
  `/funkcje/asystent` to `/funkcje/claude-chatgpt-mcp`, `/funkcje/projekty`
  to `/funkcje/czas-pracy` and the guide on invoicing without a subscription
  to the guide on free KSeF programs.
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

  @doc """
  Permanently redirects `/funkcje/asystent` to the AI page, which covers the assistant.
  """
  def assistant(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/funkcje/claude-chatgpt-mcp")
  end

  @doc """
  Permanently redirects `/funkcje/projekty` to `/funkcje/czas-pracy`.
  """
  def projects(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/funkcje/czas-pracy")
  end

  @doc """
  Permanently redirects `/poradnik/program-do-faktur-bez-abonamentu` to the
  guide on free KSeF programs, which answers the same queries.
  """
  def free_programs(conn, _params) do
    conn
    |> put_status(301)
    |> redirect(to: ~p"/poradnik/darmowe-programy-ksef")
  end
end
