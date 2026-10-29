defmodule FirmowidWeb.Infrastructure.Hooks.Locale do
  @moduledoc """
  Uses the language of the session in the LiveView process, which does not share
  the Gettext locale set by `FirmowidWeb.Infrastructure.Plugs.Locale`.
  """

  alias FirmowidWeb.Infrastructure.Plugs.Locale
  alias Phoenix.LiveView.Socket

  @doc "Puts the session's language, if one was chosen, as the Gettext locale."
  @spec on_mount(:default, map() | :not_mounted_at_router, map(), Socket.t()) ::
          {:cont, Socket.t()}
  def on_mount(:default, _params, session, socket) do
    if locale = session[Locale.session_key()], do: Gettext.put_locale(Firmowid.Gettext, locale)

    {:cont, socket}
  end
end
