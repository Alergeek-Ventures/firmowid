defmodule FirmowidWeb.Infrastructure.Controllers.Locale do
  @moduledoc """
  Switches the interface language.

  The choice is kept in the session and, for a signed-in user, saved on the
  account so it follows them to other devices. The user returns to the page the
  switch was made from.
  """
  use FirmowidWeb, :controller

  alias Firmowid.Core
  alias FirmowidWeb.Infrastructure.Plugs.Locale

  @locales Enum.map(Locale.languages(), &elem(&1, 0))

  @doc "Selects the language given in the `jezyk` param."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"jezyk" => locale}) when locale in @locales do
    if user = conn.assigns[:current_user], do: Core.set_user_locale!(user, locale, actor: user)

    conn
    |> put_session(Locale.session_key(), locale)
    |> redirect(to: return_path(conn))
  end

  # Only the path of the referring page is kept, so the redirect cannot leave the site.
  defp return_path(conn) do
    with [referer] <- get_req_header(conn, "referer"),
         %URI{path: path, query: query} when is_binary(path) <- URI.parse(referer),
         path = if(query, do: path <> "?" <> query, else: path),
         :ok <- Phoenix.URL.classify_local_path(path) do
      path
    else
      _ -> ~p"/"
    end
  end
end
