defmodule FirmowidWeb.ContentController do
  use FirmowidWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    conn =
      conn
      |> assign(:page_title, "Zarządzanie firmą znów może być przyjemne")

    render(conn, :home, layout: false)
  end

  def finances(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    conn =
      conn
      |> assign(:page_title, "Finanse Twojej organizacji")

    render(conn, :finances)
  end

  def settings(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    conn =
      conn
      |> assign(:page_title, "Ustawienia")

    render(conn, :settings)
  end
end
