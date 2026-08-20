defmodule Firmowid.Ash.Core.Emails do
  @moduledoc """
  Transactional email delivery for authentication flows.

  Sends confirmation, password reset, and email change instructions
  via Swoosh. Called by `AshAuthentication.Sender` implementations.
  """

  import Swoosh.Email

  alias Firmowid.Mailer

  @doc """
  Deliver account confirmation instructions to the given user.
  """
  @spec deliver_confirmation_instructions(
          user :: map(),
          url :: String.t(),
          email_change? :: boolean()
        ) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_confirmation_instructions(user, url, email_change? \\ false) do
    deliver(
      to_string(user.email),
      "Potwierdź adres email",
      confirmation_body(user.email, url, email_change?)
    )
  end

  defp confirmation_body(email, url, true) do
    """

    ==============================

    Cześć #{email},

    Otwórz poniższy adres, a następnie na wyświetlonej stronie kliknij przycisk potwierdzenia adresu email:

    #{url}

    Jeśli nie prosiłeś o zmianę adresu email, zignoruj tę wiadomość.

    ==============================
    """
  end

  defp confirmation_body(email, url, false) do
    """

    ==============================

    Cześć #{email},

    Otwórz poniższy adres, a następnie na wyświetlonej stronie kliknij przycisk potwierdzenia adresu email:

    #{url}

    Jeśli nie zakładałeś konta, zignoruj tę wiadomość.

    ==============================
    """
  end

  @doc """
  Deliver password reset instructions to the given user.
  """
  @spec deliver_reset_password_instructions(user :: map(), url :: String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_reset_password_instructions(user, url) do
    deliver(to_string(user.email), "Instrukcje resetowania hasła", """

    ==============================

    Cześć #{user.email},

    Możesz zresetować swoje hasło odwiedzając poniższy adres:

    #{url}

    Jeśli nie prosiłeś o tę zmianę, zignoruj tę wiadomość.

    ==============================
    """)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      # NOTE: sender email is intentionally hardcoded — this is the verified Resend
      # sender identity. Changing it requires updating Resend DNS records.
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
