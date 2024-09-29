defmodule FirmowidWeb.ContentController do
  use FirmowidWeb, :controller

  def settings(conn, _params) do
    conn =
      conn
      |> assign(:page_title, "Ustawienia")

    render(conn, :settings)
  end
end
