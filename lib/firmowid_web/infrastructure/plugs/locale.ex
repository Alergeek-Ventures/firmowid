defmodule FirmowidWeb.Infrastructure.Plugs.Locale do
  @moduledoc """
  Sets the interface language of the request.

  A signed-in user's saved language wins over the one chosen in the session. The
  session keeps the effective language, so LiveViews mounted from the page use it
  too (see `FirmowidWeb.Infrastructure.Hooks.Locale`). Without either, the Gettext
  default (Polish) applies.
  """

  @behaviour Plug

  import Plug.Conn

  @session_key "locale"
  @languages [{"pl", "Polski"}, {"en", "English"}, {"uk", "Українська"}]

  @doc "The interface languages as `{locale, name in that language}`, in display order."
  @spec languages() :: [{String.t(), String.t()}]
  def languages, do: @languages

  @doc "The session key holding the chosen language."
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case locale(conn) do
      nil ->
        conn

      locale ->
        Gettext.put_locale(Firmowid.Gettext, locale)
        {:ok, _locale} = Firmowid.Cldr.put_locale(locale)

        if get_session(conn, @session_key) == locale,
          do: conn,
          else: put_session(conn, @session_key, locale)
    end
  end

  defp locale(%{assigns: %{current_user: %{locale: locale}}}) when not is_nil(locale), do: Atom.to_string(locale)

  defp locale(conn), do: get_session(conn, @session_key)
end
