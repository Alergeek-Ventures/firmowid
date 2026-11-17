defmodule Firmowid.Billing.Payment.Changes.FollowUpDecline do
  @moduledoc """
  Follows up a declined attempt once the decline is committed: cancels its Tpay transaction,
  then emails the organization's admins.

  A declined card charge stays open at Tpay, and its payment link could still be paid later,
  after the next attempt or after the payment failed, so it is cancelled. A charge Tpay
  rejected has no transaction to cancel.

  The email says the card will be tried again, or, after the last attempt, that the
  organization is back on Free. The latter only when the failure ended the subscription
  (`end_reason: :payment_failed`, which moves the organization to Free); a subscription that
  had already ended, such as for a plan set by hand, changed nothing the admins need to hear
  about. Only a period's payment emails: the admin who asked for an upgrade sees its outcome
  at once.

  The decline stays recorded whatever happens here. The email goes out even when the cancel
  failed; then the cancel's error, else the email's, is returned as the action's error, so it
  is reported, not retried.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing
  alias Firmowid.Billing.SubscriptionEmails
  alias Firmowid.Billing.Tpay.Client

  @doc "Cancels the declined attempt's transaction and sends the decline email after the transaction commits."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      %{data: %{status: :charging} = previous}, {:ok, %{status: status} = payment}
      when status in [:declined, :failed] ->
        cancelled = cancel(payment.tpay_transaction_id)
        emailed = email(previous.kind, payment)

        with :ok <- cancelled, {:ok, _email} <- emailed, do: {:ok, payment}

      _changeset, result ->
        result
    end)
  end

  defp cancel(nil), do: :ok
  defp cancel(transaction_id), do: Client.cancel_transaction(transaction_id)

  defp email(:period, %{status: :declined} = payment), do: SubscriptionEmails.payment_declined(payment)

  defp email(:period, %{status: :failed} = payment) do
    case Ash.load(payment, :subscription, scope: Billing.scope(payment.organization_id)) do
      {:ok, %{subscription: %{end_reason: :payment_failed}}} ->
        SubscriptionEmails.payment_failed(payment)

      {:ok, _ended_otherwise} ->
        {:ok, nil}

      {:error, error} ->
        {:error, error}
    end
  end

  defp email(:upgrade, _payment), do: {:ok, nil}
end
