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
  alias Assent.HTTPAdapter.HTTPResponse
  alias Assent.InvalidResponseError
  alias Firmowid.Analytics
  alias Firmowid.Core
  alias Firmowid.Core.Member
  alias FirmowidWeb.Infrastructure.Plugs.Locale
  alias FirmowidWeb.Infrastructure.UserAuth

  require Logger

  @doc """
  Success callback after authentication (password sign-in, Google OAuth, etc.)

  A blocked account (see the User `:access_block` calculation) gets no session; it is
  sent to the page explaining the block instead.
  """
  def success(conn, {:password, :reset_request}, _user, _token) do
    conn
    |> delete_session(:return_to)
    |> put_flash(
      :info,
      gettext("If the account exists, we have sent password reset instructions.")
    )
    |> redirect(to: ~p"/zaloguj")
  end

  def success(conn, activity, user, token) do
    if activity == {:password, :register}, do: Analytics.capture_account_created(user, :password)

    user =
      user
      |> Core.load_member(selected_organization_id(user))
      |> Ash.load!(:access_block, actor: user)

    case user.access_block do
      nil -> sign_in(conn, activity, user, token)
      block -> deny_sign_in(conn, user, block)
    end
  end

  # Keeps the member the sign-in action selected: Google sign-in imports the avatar
  # into the other members too, which makes the most recently updated one (the
  # default) a different organization.
  defp selected_organization_id(%{member: %Member{organization_id: organization_id}}), do: organization_id

  defp selected_organization_id(_user), do: nil

  defp sign_in(conn, activity, user, token) do
    return_to =
      get_session(conn, :return_to) ||
        UserAuth.signed_in_path_for_user(user, selected_organization_id(user))

    conn =
      conn
      |> renew_session()
      |> delete_session(:return_to)
      |> UserAuth.put_organization(user)
      |> store_in_session(user)
      |> set_live_socket_id(token)
      |> Helpers.maybe_put_remember_me_cookies(conn.private[:ash_authentication])
      |> assign(:current_user, user)
      |> maybe_put_sign_in_toast(activity)
      |> redirect(to: return_to)

    case activity do
      {method, _phase} when method in [:password, :google] ->
        Analytics.capture_user_signed_in(user, method)

      _ ->
        :ok
    end

    conn
  end

  defp maybe_put_sign_in_toast(conn, {:password, :reset}),
    do: LiveToast.put_toast(conn, :success, gettext("Password changed successfully"))

  defp maybe_put_sign_in_toast(conn, {:confirm, :confirm}),
    do: LiveToast.put_toast(conn, :success, gettext("Email address has been confirmed."))

  defp maybe_put_sign_in_toast(conn, _activity), do: conn

  defp deny_sign_in(conn, _user, :account_disabled) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/konto-wylaczone")
  end

  defp deny_sign_in(conn, user, :subscription_expired) do
    %{organization: organization} =
      user
      |> Core.list_active_members()
      |> Enum.find(&(&1.organization.owner_id == user.id and &1.organization.billing_plan == :no_plan))

    conn
    |> renew_session()
    |> redirect(to: ~p"/abonament-wygasl?#{[organizacja: organization.name]}")
  end

  @doc """
  Failure callback when authentication fails
  """
  def failure(conn, activity, reason) do
    {message, path} = failure_message_and_path(activity, reason)

    log_auth_failure(conn, activity, reason)

    conn
    |> put_flash(:error, message)
    |> keep_sign_in_email(activity)
    |> redirect(to: path)
  end

  # The login view prefills the email field from this flash.
  defp keep_sign_in_email(conn, {:password, :sign_in}), do: put_flash(conn, :email, conn.params["user"]["email"])

  defp keep_sign_in_email(conn, _activity), do: conn

  defp failure_message_and_path({:password, :register}, reason) do
    case reason do
      %Invalid{errors: errors} when is_list(errors) ->
        duplicate_email? =
          Enum.any?(errors, fn
            %Ash.Error.Changes.InvalidAttribute{field: :email} -> true
            _ -> false
          end)

        if duplicate_email? do
          {gettext("This email is already taken."), ~p"/zarejestruj"}
        else
          {account_creation_failed_message(), ~p"/zarejestruj"}
        end

      _ ->
        {account_creation_failed_message(), ~p"/zarejestruj"}
    end
  end

  defp failure_message_and_path({:password, :sign_in}, reason) do
    if unconfirmed_user_error?(reason) do
      {gettext("Your account has not been confirmed yet. Check your inbox."), ~p"/zaloguj"}
    else
      {invalid_credentials_message(), ~p"/zaloguj"}
    end
  end

  defp failure_message_and_path({:password, :reset}, _reason) do
    {gettext("Could not reset the password. The link is invalid or has expired."), ~p"/resetuj-haslo"}
  end

  defp failure_message_and_path({:password, :reset_request}, _reason) do
    {gettext("Could not send the password reset instructions. Try again."), ~p"/resetuj-haslo"}
  end

  defp failure_message_and_path({:google, _phase}, reason) do
    if unconfirmed_user_error?(reason) do
      {gettext(
         "The account with this email address is awaiting confirmation. Confirm your email or log in with your password."
       ), ~p"/zaloguj"}
    else
      {gettext("Google sign-in failed. Try again."), ~p"/zaloguj"}
    end
  end

  defp failure_message_and_path(_activity, _reason), do: {invalid_credentials_message(), ~p"/zaloguj"}

  defp invalid_credentials_message, do: gettext("Incorrect email or password.")

  defp account_creation_failed_message do
    gettext("Could not create the account. Check the form and try again.")
  end

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

  defp auth_failure_reason(%InvalidResponseError{response: %HTTPResponse{} = response}) do
    "#{inspect(InvalidResponseError)} http_status=#{response.status}" <>
      " oauth_endpoint=#{google_oauth_endpoint(response.request_url)}" <>
      " response_kind=#{term_type(response.body)} oauth_error=#{oauth_error_code(response.body)}"
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

  # Only fixed endpoint labels and OAuth error codes may leave the response.
  # Assent can also fail decoding before it attaches the request URL.
  defp google_oauth_endpoint("https://accounts.google.com/.well-known/openid-configuration"), do: :discovery

  defp google_oauth_endpoint("https://oauth2.googleapis.com/token"), do: :token
  defp google_oauth_endpoint("https://openidconnect.googleapis.com/v1/userinfo"), do: :userinfo
  defp google_oauth_endpoint("https://www.googleapis.com/oauth2/v3/certs"), do: :jwks
  defp google_oauth_endpoint(_url), do: :unknown

  defp oauth_error_code(%{"error" => code})
       when code in ~w(invalid_request invalid_client invalid_grant unauthorized_client unsupported_grant_type invalid_scope access_denied server_error temporarily_unavailable),
       do: code

  defp oauth_error_code(%{"error" => _error}), do: :other
  defp oauth_error_code(_body), do: :none

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
    |> revoke_impersonated_session()
    |> clear_session(:firmowid)
    |> Helpers.delete_all_remember_me_cookies(:firmowid)
    |> LiveToast.put_toast(:notice, gettext("Signed out."))
    |> redirect(to: ~p"/")
  end

  defp revoke_impersonated_session(conn) do
    case get_session(conn, "impersonator_token") do
      nil ->
        conn

      token ->
        # Revoke the owner's token first; clear_session/2 then revokes the
        # parked superuser token using the same authentication library path.
        conn
        |> AshAuthentication.Plug.Helpers.revoke_session_tokens(:firmowid)
        |> put_session(:user_token, token)
    end
  end

  defp renew_session(conn) do
    locale = get_session(conn, Locale.session_key())
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> Plug.Conn.clear_session()
    |> put_session(Locale.session_key(), locale)
  end
end
