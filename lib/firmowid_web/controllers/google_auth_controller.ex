defmodule FirmowidWeb.GoogleAuthController do
  use FirmowidWeb, :controller

  alias Firmowid.Accounts
  alias FirmowidWeb.UserAuth

  @doc """
  Initiates the Google OAuth flow by redirecting to Google's authorization page.
  """
  def request(conn, _params) do
    google_auth_url = ElixirAuthGoogle.generate_oauth_url(conn)
    redirect(conn, external: google_auth_url)
  end

  @doc """
  Handles the callback from Google OAuth.

  This function:
  1. Exchanges the authorization code for user information
  2. Creates or finds the user in the database
  3. Logs the user in
  4. Redirects to the appropriate page
  """
  def callback(conn, %{"code" => code}) do
    case ElixirAuthGoogle.get_token(code, conn) do
      {:ok, token} ->
        case ElixirAuthGoogle.get_user_profile(token.access_token) do
          {:ok, profile} ->
            handle_user_profile(conn, profile)

          {:error, error} ->
            conn
            |> put_flash(:error, "Nie udało się pobrać profilu użytkownika z Google: #{inspect(error)}")
            |> redirect(to: ~p"/zaloguj")
        end

      {:error, error} ->
        conn
        |> put_flash(:error, "Nie udało się uwierzytelnić przez Google: #{inspect(error)}")
        |> redirect(to: ~p"/zaloguj")
    end
  end

  def callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Uwierzytelnianie zostało anulowane lub nie powiodło się: #{error}")
    |> redirect(to: ~p"/zaloguj")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Nieprawidłowe wywołanie OAuth")
    |> redirect(to: ~p"/zaloguj")
  end

  defp handle_user_profile(conn, profile) do
    user_params = %{
      email: profile.email,
      name: profile.name,
      provider: "google",
      provider_id: profile.sub
    }

    case Accounts.get_or_create_oauth_user(user_params) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, :email_already_exists} ->
        # User exists with password - send email to link accounts
        # Re-fetch user to ensure they still exist and handle race condition
        case Accounts.get_user_by_email(user_params.email) do
          %Accounts.User{} = user ->
            Accounts.deliver_link_google_account_instructions(
              user,
              profile,
              &url(~p"/auth/google/link/#{&1}")
            )

            conn
            |> put_flash(
              :info,
              "Znaleźliśmy istniejące konto z tym adresem e-mail. Wysłaliśmy Ci wiadomość z instrukcjami, jak połączyć konto Google."
            )
            |> redirect(to: ~p"/zaloguj")

          nil ->
            # Rare race condition: user was deleted between checks
            # Retry the whole OAuth flow since user no longer exists
            case Accounts.get_or_create_oauth_user(user_params) do
              {:ok, user} ->
                UserAuth.log_in_user(conn, user)

              _error ->
                conn
                |> put_flash(:error, "Wystąpił błąd. Spróbuj ponownie.")
                |> redirect(to: ~p"/zaloguj")
            end
        end

      {:error, :provider_mismatch} ->
        conn
        |> put_flash(:error, "Wystąpił błąd podczas uwierzytelniania. Spróbuj ponownie.")
        |> redirect(to: ~p"/zaloguj")

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_flash(:error, "Nie udało się utworzyć konta: #{inspect(errors)}")
        |> redirect(to: ~p"/zaloguj")
    end
  end

  @doc """
  Handles the account linking confirmation when user clicks the link in their email.

  This function:
  1. Verifies the token
  2. Links the Google account to the existing user
  3. Logs the user in
  4. Redirects to the dashboard
  """
  def link(conn, %{"token" => token}) do
    case Accounts.get_user_by_link_google_token(token) do
      {:ok, user} ->
        case Accounts.link_google_account_with_token(user, token) do
          {:ok, updated_user} ->
            conn
            |> put_flash(:info, "Twoje konto Google zostało pomyślnie połączone! Możesz teraz logować się przez Google.")
            |> UserAuth.log_in_user(updated_user)

          {:error, :invalid_token} ->
            conn
            |> put_flash(
              :error,
              "Link do połączenia konta jest nieprawidłowy lub wygasł. Spróbuj zalogować się przez Google ponownie."
            )
            |> redirect(to: ~p"/zaloguj")

          {:error, :google_account_already_linked} ->
            conn
            |> put_flash(:error, "To konto Google jest już połączone z innym użytkownikiem.")
            |> redirect(to: ~p"/zaloguj")

          {:error, %Ecto.Changeset{}} ->
            conn
            |> put_flash(:error, "Wystąpił błąd podczas łączenia konta. Spróbuj ponownie.")
            |> redirect(to: ~p"/zaloguj")
        end

      :error ->
        conn
        |> put_flash(
          :error,
          "Link do połączenia konta jest nieprawidłowy lub wygasł. Spróbuj zalogować się przez Google ponownie."
        )
        |> redirect(to: ~p"/zaloguj")
    end
  end
end
