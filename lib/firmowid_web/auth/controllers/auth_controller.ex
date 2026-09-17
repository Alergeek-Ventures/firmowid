defmodule FirmowidWeb.Auth.Controllers.AuthController do
  @moduledoc """
  Ash Authentication controller.

  Handles authentication success/failure callbacks, logout, and remember-me
  cookie management. Replaces the legacy Session controller.
  """
  use FirmowidWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias AshAuthentication.Errors.AuthenticationFailed
  alias AshAuthentication.Strategy.RememberMe.Plug.Helpers
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents

  require Logger

  @doc """
  Success callback after authentication (password sign-in, Google OAuth, etc.)
  """
  def success(conn, {:password, :reset}, user, token) do
    return_to = get_session(conn, :return_to) || UserAuth.signed_in_path_for_user(user)

    conn
    |> renew_session()
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> set_live_socket_id(token)
    |> Helpers.maybe_put_remember_me_cookies(conn.private[:ash_authentication])
    |> assign(:current_user, user)
    |> LiveToast.put_toast(:success, "Hasło zmienione poprawnie")
    |> redirect(to: return_to)
  end

  def success(conn, {:password, :register}, user, token) do
    PosthogBusinessEvents.capture_account_created(conn, user)

    return_to = get_session(conn, :return_to) || UserAuth.signed_in_path_for_user(user)

    conn
    |> renew_session()
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> set_live_socket_id(token)
    |> Helpers.maybe_put_remember_me_cookies(conn.private[:ash_authentication])
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  def success(conn, {:password, :reset_request}, _user, _token) do
    conn
    |> delete_session(:return_to)
    |> put_flash(:info, "Jeśli konto istnieje, wysłaliśmy instrukcje resetowania hasła.")
    |> redirect(to: ~p"/zaloguj")
  end

  def success(conn, {:confirm, :confirm}, user, token) do
    return_to = get_session(conn, :return_to) || UserAuth.signed_in_path_for_user(user)

    conn
    |> renew_session()
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> set_live_socket_id(token)
    |> Helpers.maybe_put_remember_me_cookies(conn.private[:ash_authentication])
    |> assign(:current_user, user)
    |> LiveToast.put_toast(:success, "Adres email został potwierdzony.")
    |> redirect(to: return_to)
  end

  def success(conn, _activity, user, token) do
    return_to = get_session(conn, :return_to) || UserAuth.signed_in_path_for_user(user)

    conn
    |> renew_session()
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> set_live_socket_id(token)
    |> Helpers.maybe_put_remember_me_cookies(conn.private[:ash_authentication])
    |> assign(:current_user, user)
    |> redirect(to: return_to)
  end

  @doc """
  Failure callback when authentication fails
  """
  def failure(conn, activity, reason) do
    {message, path} = failure_message_and_path(activity, reason)

    log_auth_failure(conn, activity, reason)

    conn
    |> put_flash(:error, message)
    |> redirect(to: path)
  end

  defp failure_message_and_path({:password, :register}, reason) do
    case reason do
      %Invalid{errors: errors} when is_list(errors) ->
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

  defp failure_message_and_path({:password, :reset}, _reason) do
    {"Nie udało się zresetować hasła. Link jest nieprawidłowy lub wygasł.", ~p"/resetuj-haslo"}
  end

  defp failure_message_and_path({:password, :reset_request}, _reason) do
    {"Nie udało się wysłać instrukcji resetowania hasła. Spróbuj ponownie.", ~p"/resetuj-haslo"}
  end

  defp failure_message_and_path({:google, _phase}, reason) do
    if unconfirmed_user_error?(reason) do
      {"Konto z tym adresem email czeka na potwierdzenie. Potwierdź email lub zaloguj się hasłem.", ~p"/zaloguj"}
    else
      {"Logowanie Google nie powiodło się. Spróbuj ponownie.", ~p"/zaloguj"}
    end
  end

  defp failure_message_and_path(_activity, _reason), do: {"Niewłaściwy email lub hasło.", ~p"/zaloguj"}

  defp log_auth_failure(conn, {:google, phase}, reason) do
    Logger.warning(
      "Google authentication failed phase=#{phase} path=#{conn.request_path} reason=#{auth_failure_reason(reason)}"
    )
  end

  defp log_auth_failure(_conn, _activity, _reason), do: :ok

  defp auth_failure_reason(nil), do: "nil"

  defp auth_failure_reason(%AuthenticationFailed{caused_by: caused_by}) do
    "#{inspect(AuthenticationFailed)}/#{auth_failure_reason(caused_by)}"
  end

  defp auth_failure_reason(%Invalid{errors: errors}) when is_list(errors) do
    "#{inspect(Invalid)}/#{auth_failure_errors(errors)}"
  end

  defp auth_failure_reason(%Forbidden{errors: errors}) when is_list(errors) do
    "#{inspect(Forbidden)}/#{auth_failure_errors(errors)}"
  end

  defp auth_failure_reason(%Postgrex.Error{postgres: %{code: code}}) do
    "#{inspect(Postgrex.Error)}/#{code}"
  end

  defp auth_failure_reason(%{__struct__: struct}), do: inspect(struct)
  defp auth_failure_reason(reason), do: reason |> term_type() |> to_string()

  defp auth_failure_errors(errors) do
    errors
    |> Enum.map(&auth_failure_reason/1)
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp term_type(reason) when is_boolean(reason), do: :boolean
  defp term_type(reason) when is_atom(reason), do: :atom
  defp term_type(reason) when is_binary(reason), do: :binary
  defp term_type(reason) when is_integer(reason), do: :integer
  defp term_type(reason) when is_float(reason), do: :float
  defp term_type(reason) when is_list(reason), do: :list
  defp term_type(reason) when is_map(reason), do: :map
  defp term_type(reason) when is_tuple(reason), do: :tuple
  defp term_type(_reason), do: :term

  # Detects confirmation-related errors in both the password and OAuth failure shapes.
  #
  # Password sign-in: AuthenticationFailed wrapping UnconfirmedUser directly in caused_by.
  # OAuth (prevent_hijacking): AuthenticationFailed wrapping Forbidden whose errors list
  # contains CannotConfirmUnconfirmedUser.
  defp unconfirmed_user_error?(%AuthenticationFailed{caused_by: %AshAuthentication.Errors.UnconfirmedUser{}}), do: true

  defp unconfirmed_user_error?(%AuthenticationFailed{caused_by: %Forbidden{errors: errors}}) when is_list(errors) do
    Enum.any?(errors, &match?(%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}, &1))
  end

  defp unconfirmed_user_error?(_), do: false

  @doc """
  Sign out action — clears session and remember-me cookies.

  `clear_session/2` revokes the session token; the token resource notifier
  broadcasts the LiveView disconnect, including for revocations initiated by
  other flows.
  """
  def sign_out(conn, _params) do
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
