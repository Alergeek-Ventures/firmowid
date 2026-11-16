defmodule Firmowid.Billing.Payment.Changes.EndSubscriptionOnFailure do
  @moduledoc """
  Ends the subscription of a payment that just failed, in the same transaction, with the
  reason `:payment_failed`, which puts the organization back on Free.
  """

  use Ash.Resource.Change

  alias Ash.Resource.Change.Context
  alias Firmowid.Billing

  @doc "Ends the subscription after the payment is saved as failed."
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, payment ->
      if payment.status == :failed and changeset.data.status != :failed do
        end_subscription(payment)
      else
        {:ok, payment}
      end
    end)
  end

  defp end_subscription(payment) do
    scope = Billing.scope(payment.organization_id)

    with {:ok, %{subscription: subscription}} <- Ash.load(payment, :subscription, scope: scope),
         {:ok, _subscription} <- end_open(subscription, scope) do
      {:ok, payment}
    end
  end

  # A subscription already ended for another reason (a plan set by hand) stays as it ended.
  defp end_open(%{status: :ended} = subscription, _scope), do: {:ok, subscription}

  defp end_open(subscription, scope), do: Billing.end_subscription(subscription, %{reason: :payment_failed}, scope: scope)
end
