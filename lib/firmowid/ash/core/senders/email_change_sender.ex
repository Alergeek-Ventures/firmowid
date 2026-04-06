defmodule Firmowid.Ash.Core.Senders.EmailChangeSender do
  @moduledoc """
  Sends email change confirmation emails via `Firmowid.Ash.Core.Emails`.

  Used by `AshAuthentication.AddOn.Confirmation` when a user changes their
  email address.
  """
  use AshAuthentication.Sender

  alias Firmowid.Ash.Core.Emails
  alias FirmowidWeb.Core.Endpoint

  @impl true
  def send(user, token, _opts) do
    url = Endpoint.url() <> "/ustawienia/bezpieczenstwo/potwierdz/#{token}"
    _ = Emails.deliver_update_email_instructions(user, url)
    :ok
  end
end
