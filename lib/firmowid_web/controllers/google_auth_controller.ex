defmodule FirmowidWeb.GoogleAuthController do
  use FirmowidWeb, :controller

  alias Firmowid.Accounts
  alias Firmowid.Analytics
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

    # Check if user is already logged in (coming from settings page)
    current_user = conn.assigns[:current_user]

    cond do
      # User is logged in and wants to link their account
      current_user != nil && current_user.email == profile.email ->
        handle_link_for_logged_in_user(conn, current_user, profile)

      # User is logged in but trying to link different Google account
      current_user != nil ->
        conn
        |> put_flash(:error, "Ten adres e-mail Google nie pasuje do Twojego konta.")
        |> redirect(to: ~p"/ustawienia/bezpieczenstwo")

      # User is not logged in - normal OAuth flow
      true ->
        handle_oauth_login(conn, user_params, profile)
    end
  end

  defp handle_link_for_logged_in_user(conn, user, profile) do
    case user
         |> Accounts.User.link_google_changeset(profile.sub)
         |> Firmowid.Repo.update() do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:info, "Twoje konto Google zostało pomyślnie połączone!")
        |> redirect(to: ~p"/ustawienia/bezpieczenstwo")

      {:error, changeset} ->
        if has_unique_constraint_error?(changeset, :google_provider_id) do
          conn
          |> put_flash(:error, "To konto Google jest już połączone z innym użytkownikiem.")
          |> redirect(to: ~p"/ustawienia/bezpieczenstwo")
        else
          conn
          |> put_flash(:error, "Wystąpił błąd podczas łączenia konta. Spróbuj ponownie.")
          |> redirect(to: ~p"/ustawienia/bezpieczenstwo")
        end
    end
  end

  defp handle_oauth_login(conn, user_params, profile) do
    case Accounts.get_or_create_oauth_user(user_params) do
      {:ok, user} ->
        Analytics.identify(user)
        Analytics.track_event("user_log_in", user, %{auth_provider: "google"})

        UserAuth.log_in_user(conn, user)

      {:error, :email_already_exists} ->
        handle_email_already_exists(conn, user_params, profile)

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

  defp handle_email_already_exists(conn, user_params, profile) do
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
        retry_oauth_flow(conn, user_params)
    end
  end

  defp retry_oauth_flow(conn, user_params) do
    case Accounts.get_or_create_oauth_user(user_params) do
      {:ok, user} ->
        Analytics.identify(user)
        Analytics.track_event("user_log_in", user, %{auth_provider: "google"})
        UserAuth.log_in_user(conn, user)

      _error ->
        conn
        |> put_flash(:error, "Wystąpił błąd. Spróbuj ponownie.")
        |> redirect(to: ~p"/zaloguj")
    end
  end

  # Checks if a changeset has a unique constraint error for the given field
  defp has_unique_constraint_error?(%Ecto.Changeset{errors: errors}, field) do
    Enum.any?(errors, fn
      {^field, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
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
            Analytics.identify(updated_user)
            Analytics.track_event("user_log_in", updated_user, %{auth_provider: "google"})

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
