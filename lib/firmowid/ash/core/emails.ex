defmodule Firmowid.Ash.Core.Emails do
  @moduledoc """
  Transactional email delivery for authentication flows.

  Sends confirmation, password reset, and email change instructions
  via Swoosh. Called by `AshAuthentication.Sender` implementations.
  """

  use Phoenix.Component

  import Firmowid.Mailer.Components
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
    email = to_string(user.email)
    assigns = %{email: email, url: url, email_change?: email_change?}

    html =
      to_html(~H"""
      <.email preheader="Potwierdź adres email">
        <.greeting>Potwierdź adres email</.greeting>
        <.paragraph>
          Cześć {@email}, potwierdź swój adres email klikając poniższy przycisk.
        </.paragraph>
        <.button href={@url}>Potwierdź adres email</.button>
        <.fallback_link href={@url} />
        <.note>
          {if @email_change?,
            do: "Jeśli nie prosiłeś o zmianę adresu email, zignoruj tę wiadomość.",
            else: "Jeśli nie zakładałeś konta, zignoruj tę wiadomość."}
        </.note>
        <.signature />
      </.email>
      """)

    text = confirmation_body(email, url, email_change?)
    deliver(email, "Potwierdź adres email", text, html)
  end

  defp confirmation_body(email, url, email_change?) do
    notice =
      if email_change? do
        "Jeśli nie prosiłeś o zmianę adresu email, zignoruj tę wiadomość."
      else
        "Jeśli nie zakładałeś konta, zignoruj tę wiadomość."
      end

    """

    ==============================

    Cześć #{email},

    Otwórz poniższy adres, a następnie na wyświetlonej stronie kliknij przycisk potwierdzenia adresu email:

    #{url}

    #{notice}

    ==============================
    """
  end

  @doc """
  Deliver password reset instructions to the given user.
  """
  @spec deliver_reset_password_instructions(user :: map(), url :: String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_reset_password_instructions(user, url) do
    email = to_string(user.email)
    assigns = %{email: email, url: url}

    html =
      to_html(~H"""
      <.email preheader="Instrukcje resetowania hasła">
        <.greeting>Resetowanie hasła</.greeting>
        <.paragraph>
          Cześć {@email}, otrzymaliśmy prośbę o resetowanie hasła. Kliknij poniższy przycisk, aby ustawić nowe hasło.
        </.paragraph>
        <.button href={@url}>Zresetuj hasło</.button>
        <.fallback_link href={@url} />
        <.note>Jeśli nie prosiłeś o tę zmianę, zignoruj tę wiadomość.</.note>
        <.signature />
      </.email>
      """)

    text = """
    Cześć #{email},

    Możesz zresetować swoje hasło odwiedzając poniższy adres:

    #{url}

    Jeśli nie prosiłeś o tę zmianę, zignoruj tę wiadomość.
    """

    deliver(email, "Instrukcje resetowania hasła", text, html)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp deliver(recipient, subject, text_body, html_body) do
    email =
      new()
      |> to(recipient)
      # NOTE: sender email is intentionally hardcoded — this is the verified Resend
      # sender identity. Changing it requires updating Resend DNS records.
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject(subject)
      |> text_body(text_body)
      |> html_body(html_body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
