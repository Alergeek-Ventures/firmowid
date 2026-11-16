defmodule Firmowid.BillingFixtures do
  @moduledoc """
  Test helpers for card subscriptions and their payments.
  """

  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.Payment
  alias Firmowid.Billing.Subscription
  alias Firmowid.Core

  @doc """
  Seeds an active Przedsiębiorca monthly subscription with a saved card, in the current month
  unless `attrs` say otherwise, and gives its organization the subscription's plan.
  """
  @spec active_subscription!(Ecto.UUID.t(), map()) :: Subscription.t()
  def active_subscription!(organization_id, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    subscription =
      Ash.Seed.seed!(
        Subscription,
        Map.merge(
          %{
            organization_id: organization_id,
            plan: :przedsiebiorca,
            billing_period: :monthly,
            status: :active,
            tokenization_id: "TOK-#{unique}",
            card_token: "card-token-#{unique}",
            card_tail: "1234",
            activated_at: DateTime.utc_now(),
            current_period_start: Month.current(),
            current_period_end: Date.end_of_month(Month.current()),
            next_charge_on: Month.next()
          },
          attrs
        )
      )

    organization_id
    |> Core.get_organization!(authorize?: false)
    |> Ash.Seed.update!(%{billing_plan: subscription.plan})

    subscription
  end

  @doc """
  Opens the payment for the subscription's current period through `:create`, so it is priced
  from the plan catalog, then seeds `attrs` over it (such as a status reached earlier).
  """
  @spec period_payment!(Subscription.t(), map()) :: Payment.t()
  def period_payment!(subscription, attrs \\ %{}) do
    %{
      subscription_id: subscription.id,
      kind: :period,
      plan: subscription.plan,
      billing_period: subscription.billing_period,
      period_start: subscription.current_period_start,
      period_end: subscription.current_period_end,
      max_attempts: 3
    }
    |> Billing.create_payment!(scope: Billing.scope(subscription.organization_id))
    |> Ash.Seed.update!(attrs)
  end
end
