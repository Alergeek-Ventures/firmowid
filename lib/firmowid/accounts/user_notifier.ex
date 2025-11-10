defmodule Firmowid.Accounts.UserNotifier do
  @moduledoc false
  import Swoosh.Email

  alias Firmowid.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Instrukcje potwierdzenia konta", """

    ==============================

    Cześć #{user.email},

    Możesz potwierdzić swoje konto odwiedzając poniższy adres:

    #{url}

    Jeśli nie zakładałeś konta u nas, zignoruj tę wiadomość.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Instrukcje resetowania hasła", """

    ==============================

    Cześć #{user.email},

    Możesz zresetować swoje hasło odwiedzając poniższy adres:

    #{url}

    Jeśli nie prosiłeś o tę zmianę, zignoruj tę wiadomość.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Instrukcje zmiany adresu email", """

    ==============================

    Cześć #{user.email},

    Możesz zmienić swój adres email odwiedzając poniższy adres:

    #{url}

    Jeśli nie prosiłeś o tę zmianę, zignoruj tę wiadomość.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to link a Google account.
  """
  def deliver_link_google_account_instructions(user, url) do
    deliver(user.email, "Połącz swoje konto Google z Firmowid", """

    ==============================

    Cześć #{user.email},

    Ktoś próbował zalogować się na Twoje konto Firmowid przy użyciu Google.

    Jeśli to byłeś Ty, kliknij poniższy link, aby połączyć swoje konto Google
    i włączyć logowanie przez Google:

    #{url}

    Ten link wygaśnie za 24 godziny.

    Jeśli nie próbowałeś zalogować się przez Google, zignoruj tę wiadomość
    i rozważ zmianę hasła, jeśli martwisz się o bezpieczeństwo konta.

    ==============================
    """)
  end
end
