defmodule Firmowid.Ash.Core.Senders.ConfirmationSender do
  @moduledoc """
  Sends account confirmation emails via `Firmowid.Ash.Core.Emails`.

  Used by `AshAuthentication.AddOn.Confirmation` when a new user registers
  with a password strategy. Google OAuth registrations skip this via
  `auto_confirm_actions`.
  """
  use AshAuthentication.Sender

  alias Firmowid.Ash.Core.Emails
  alias FirmowidWeb.Core.Endpoint

  @impl true
  def send(user, token, _opts) do
    url = Endpoint.url() <> "/potwierdz-email/#{token}"
    _ = Emails.deliver_confirmation_instructions(user, url)
    :ok
  end
end
