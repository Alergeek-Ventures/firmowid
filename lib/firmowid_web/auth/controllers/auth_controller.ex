defmodule FirmowidWeb.Auth.Controllers.AuthController do
  @moduledoc """
  Ash Authentication controller.

  Handles authentication success/failure callbacks, logout, and remember-me
  cookie management. Replaces the legacy Session controller.
  """
  use FirmowidWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias AshAuthentication.Strategy.RememberMe.Plug.Helpers
  alias Firmowid.Analytics
  alias FirmowidWeb.Core.Endpoint

  @doc """
  Success callback after authentication (password sign-in, Google OAuth, etc.)
  """
  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/czasosledz"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> Helpers.maybe_put_remember_me_cookies(conn.private[:ash_authentication])
    |> assign(:current_user, user)
    |> then(fn conn ->
      Analytics.identify(user)
      Analytics.track_event("user_log_in", user, %{})
      conn
    end)
    |> redirect(to: return_to)
  end

  @doc """
  Failure callback when authentication fails
  """
  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Niewłaściwy email lub hasło.")
    |> redirect(to: ~p"/zaloguj")
  end

  @doc """
  Sign out action — clears session, remember-me cookies, and broadcasts disconnect
  """
  def sign_out(conn, _params) do
    # Broadcast disconnect for LiveView sessions
    if live_socket_id = get_session(conn, :live_socket_id) do
      Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> clear_session(:firmowid)
    |> Helpers.delete_all_remember_me_cookies(:firmowid)
    |> LiveToast.put_toast(:notice, "Wylogowano.")
    |> redirect(to: ~p"/")
  end
end
