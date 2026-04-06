defmodule Firmowid.Ash.Core.Senders.PasswordResetSender do
  @moduledoc """
  Sends password reset emails via `Firmowid.Ash.Core.Emails`.

  Used by `AshAuthentication.Strategy.Password` resettable configuration.
  """
  use AshAuthentication.Sender

  alias Firmowid.Ash.Core.Emails
  alias FirmowidWeb.Core.Endpoint

  @impl true
  def send(user, token, _opts) do
    url = Endpoint.url() <> "/resetuj-haslo/#{token}"
    _ = Emails.deliver_reset_password_instructions(user, url)
    :ok
  end
end
