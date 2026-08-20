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
  def send(user, token, opts) do
    url = Endpoint.url() <> "/potwierdz-email/#{token}"
    recipient = proposed_email(opts) || user.email
    _ = Emails.deliver_confirmation_instructions(%{user | email: recipient}, url)
    :ok
  end

  defp proposed_email(opts) do
    opts
    |> Keyword.get(:changeset)
    |> case do
      nil -> nil
      changeset -> Ash.Changeset.get_attribute(changeset, :email)
    end
  end
end
