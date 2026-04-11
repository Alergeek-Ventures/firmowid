defmodule FirmowidWeb.Auth.Controllers.AuthController do
  @moduledoc """
  Ash Authentication controller.

  Handles authentication success/failure callbacks, logout, and remember-me
  cookie management. Replaces the legacy Session controller.
  """
  use FirmowidWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias AshAuthentication.Strategy.RememberMe.Plug.Helpers
  alias FirmowidWeb.Core.Endpoint

  @doc """
  Success callback after authentication (password sign-in, Google OAuth, etc.)
  """
  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/czasosledz"

    conn
    |> renew_session()
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> Helpers.maybe_put_remember_me_cookies(conn.private[:ash_authentication])
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  @doc """
  Failure callback when authentication fails
  """
  def failure(conn, activity, reason) do
    {message, path} = failure_message_and_path(activity, reason)

    conn
    |> put_flash(:error, message)
    |> redirect(to: path)
  end

  defp failure_message_and_path({:password, :register}, reason) do
    case reason do
      %Ash.Error.Invalid{errors: errors} when is_list(errors) ->
        duplicate_email? =
          Enum.any?(errors, fn
            %Ash.Error.Changes.InvalidAttribute{field: :email} -> true
            _ -> false
          end)

        if duplicate_email? do
          {"Taki email jest już zajęty.", ~p"/zarejestruj"}
        else
          {"Nie udało się utworzyć konta. Sprawdź formularz i spróbuj ponownie.", ~p"/zarejestruj"}
        end

      _ ->
        {"Nie udało się utworzyć konta. Sprawdź formularz i spróbuj ponownie.", ~p"/zarejestruj"}
    end
  end

  defp failure_message_and_path(_activity, _reason), do: {"Niewłaściwy email lub hasło.", ~p"/zaloguj"}

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

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> Plug.Conn.clear_session()
  end
end
