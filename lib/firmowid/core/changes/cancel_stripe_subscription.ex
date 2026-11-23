defmodule Firmowid.Core.Changes.CancelStripeSubscription do
  @moduledoc """
  Stops everything Stripe could still charge for the organization's subscription, so a plan set
  by hand or a deleted organization is never charged again: the subscription is cancelled at
  Stripe at once, without a final invoice or a prorated credit (both are off by default when
  cancelling). A subscription Stripe has already cancelled leaves nothing to stop.
  """

  use Ash.Resource.Change

  alias Firmowid.Billing.StripeTerms

  @doc "Cancels the Stripe subscription before the write and forgets it on an update."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.data.stripe_subscription_id do
        nil ->
          changeset

        stripe_subscription_id ->
          case StripeTerms.request(:delete, "/v1/subscriptions/#{stripe_subscription_id}") do
            {:ok, _cancelled} -> forget(changeset)
            # Stripe answers 404 for a subscription it has already cancelled.
            {:error, %Stripe.Error{extra: %{http_status: 404}}} -> forget(changeset)
            {:error, error} -> Ash.Changeset.add_error(changeset, error)
          end
      end
    end)
  end

  defp forget(%{action_type: :update} = changeset),
    do: Ash.Changeset.force_change_attribute(changeset, :stripe_subscription_id, nil)

  defp forget(changeset), do: changeset
end
