defmodule Firmowid.Core.Changes.FollowStripeSubscription do
  @moduledoc """
  Makes the organization's plan follow a Stripe subscription (the `:stripe_subscription`
  argument, as Stripe returns it now, with its customer expanded). It only copies Stripe's current state, so applying it
  again, or after an older event, leaves the plan and the subscription as they are. The action's
  plan change hook still runs then and checks a pending plan limit decision.

  A subscription that gives the plan (`StripeTerms.lifecycle/1` `:live`) sets the plan of its
  price and becomes the organization's subscription. When the organization's own subscription
  is over, the plan returns to Free, and a customer deleted at Stripe is forgotten. A
  subscription that is over and is not the organization's (ended by a plan set by hand, or never
  the one it followed) changes nothing, and neither does one whose first payment is still
  pending.
  """

  use Ash.Resource.Change

  alias Firmowid.Billing.StripeTerms

  @doc "Sets the plan and the subscription id from the Stripe subscription."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    %{
      "id" => id,
      "status" => status,
      "customer" => customer,
      "items" => %{"data" => [item]}
    } = Ash.Changeset.get_argument(changeset, :stripe_subscription)

    case {StripeTerms.lifecycle(status), changeset.data.stripe_subscription_id} do
      {:live, current} when current in [nil, id] ->
        follow(changeset, id, customer["id"], item["price"])

      {:live, other} ->
        Ash.Changeset.add_error(
          changeset,
          "The organization follows the Stripe subscription #{other}; #{id} is a second one. " <>
            "Cancel one of them in the Stripe Dashboard"
        )

      {:over, ^id} ->
        changeset
        |> Ash.Changeset.force_change_attributes(%{
          billing_plan: :free,
          stripe_subscription_id: nil
        })
        |> forget_deleted_customer(customer)

      {_pending_or_not_followed, _current} ->
        changeset
    end
  end

  # A customer deleted at Stripe cannot buy again, so the next purchase creates a new one.
  defp forget_deleted_customer(changeset, %{"deleted" => true}),
    do: Ash.Changeset.force_change_attribute(changeset, :stripe_customer_id, nil)

  defp forget_deleted_customer(changeset, _customer), do: changeset

  defp follow(changeset, id, customer, price) do
    case StripeTerms.plan_of(price) do
      {:ok, {plan, _billing_period}} ->
        Ash.Changeset.force_change_attributes(changeset, %{
          billing_plan: plan,
          stripe_subscription_id: id,
          stripe_customer_id: customer
        })

      :error ->
        Ash.Changeset.add_error(
          changeset,
          "Stripe subscription #{id} has a price that is not a Firmowid plan"
        )
    end
  end
end
