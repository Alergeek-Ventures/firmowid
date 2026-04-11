defmodule FirmowidWeb.Auth.Controllers.AuthController do
  @moduledoc """
  Ash Authentication controller.

  Handles authentication success/failure callbacks, logout, and remember-me
  cookie management. Replaces the legacy Session controller.
  """
  use FirmowidWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias AshAuthentication.Errors.AuthenticationFailed
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

  defp failure_message_and_path({:password, :sign_in}, reason) do
    if unconfirmed_user_error?(reason) do
      {"Twoje konto nie zostało jeszcze potwierdzone. Sprawdź skrzynkę pocztową.", ~p"/zaloguj"}
    else
      {"Niewłaściwy email lub hasło.", ~p"/zaloguj"}
    end
  end

  defp failure_message_and_path({:google, _phase}, reason) do
    if unconfirmed_user_error?(reason) do
      {"Konto z tym adresem email czeka na potwierdzenie. Potwierdź email lub zaloguj się hasłem.", ~p"/zaloguj"}
    else
      {"Logowanie Google nie powiodło się. Spróbuj ponownie.", ~p"/zaloguj"}
    end
  end

  defp failure_message_and_path(_activity, _reason), do: {"Niewłaściwy email lub hasło.", ~p"/zaloguj"}

  # Detects confirmation-related errors in both the password and OAuth failure shapes.
  #
  # Password sign-in: AuthenticationFailed wrapping UnconfirmedUser directly in caused_by.
  # OAuth (prevent_hijacking): AuthenticationFailed wrapping Forbidden whose errors list
  # contains CannotConfirmUnconfirmedUser.
  defp unconfirmed_user_error?(%AuthenticationFailed{caused_by: %AshAuthentication.Errors.UnconfirmedUser{}}), do: true

  defp unconfirmed_user_error?(%AuthenticationFailed{caused_by: %Ash.Error.Forbidden{errors: errors}})
       when is_list(errors) do
    Enum.any?(errors, &match?(%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}, &1))
  end

  defp unconfirmed_user_error?(_), do: false

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
