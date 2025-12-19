defmodule FirmowidWeb.Plugs.RedirectTrailing do
  @moduledoc """
  Plug that redirects requests with trailing slashes to their non-trailing equivalents.

  For example, `/users/` will be redirected to `/users` with a 301 status code.
  The root path `/` is excluded from this redirect.
  """

  use FirmowidWeb, :controller

  def redirect_trailing_slash(conn, _opts) do
    if conn.request_path != "/" && String.last(conn.request_path) == "/" do
      conn
      |> put_status(301)
      |> redirect(to: String.slice(conn.request_path, 0..-2//1))
      |> halt()
    else
      conn
    end
  end
end
