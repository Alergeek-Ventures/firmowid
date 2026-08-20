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

  require Logger

  @impl true
  def send(user, token, opts) do
    url = Endpoint.url() <> "/potwierdz-email/#{token}"
    recipient = proposed_email(opts) || user.email

    case Emails.deliver_confirmation_instructions(
           %{user | email: recipient},
           url,
           email_change?(opts)
         ) do
      {:ok, _email} ->
        :ok

      {:error, reason} ->
        report_delivery_failure(reason)
        {:error, reason}
    end
  end

  defp proposed_email(opts) do
    opts
    |> Keyword.get(:changeset)
    |> case do
      nil -> nil
      changeset -> Ash.Changeset.get_attribute(changeset, :email)
    end
  end

  defp email_change?(opts) do
    case Keyword.get(opts, :changeset) do
      %{action: %{name: :change_email}} -> true
      _ -> false
    end
  end

  defp report_delivery_failure(reason) do
    Sentry.capture_exception(RuntimeError.exception("Confirmation email delivery failed"),
      tags: %{source: "confirmation_email"},
      extra: %{reason: inspect(reason)}
    )
  rescue
    error ->
      Logger.warning("Failed to report confirmation email delivery failure: #{Exception.message(error)}")
  end
end
