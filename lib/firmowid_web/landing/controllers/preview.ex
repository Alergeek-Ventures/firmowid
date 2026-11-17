defmodule FirmowidWeb.Landing.Controllers.Preview do
  @moduledoc """
  Serves the preview of the new home page at `/landing`.

  The page is a self-contained static document kept in `priv/static/landing`.
  It is not linked from anywhere and is excluded from search indexes.
  """
  use FirmowidWeb, :controller

  @page_path Application.app_dir(:firmowid, "priv/static/landing/index.html")
  @external_resource @page_path
  @page File.read!(@page_path)

  @doc "Returns the preview page with a header that keeps it out of search indexes."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    conn
    |> put_resp_header("x-robots-tag", "noindex")
    |> html(@page)
  end
end
