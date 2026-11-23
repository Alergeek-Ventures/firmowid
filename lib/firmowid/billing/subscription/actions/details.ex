defmodule Firmowid.Billing.Subscription.Actions.Details do
  @moduledoc """
  Reads the organization's subscription from Stripe, as the screens tell about it: the plan and
  billing period of its price, the amount Stripe charges for the period, the day Stripe charges
  next, whether Stripe ends it at the end of the current period and whether it trials. An
  organization without a subscription has none.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core

  @doc "Returns the subscription as Stripe reports it, or nil."
  @spec run(Ash.ActionInput.t(), keyword(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, map() | nil} | {:error, term()}
  @impl true
  def run(_input, _opts, context) do
    with {:ok, organization} <-
           Core.get_organization(context.tenant, Ash.Context.to_opts(context)) do
      details(organization)
    end
  end

  defp details(%{stripe_subscription_id: nil}), do: {:ok, nil}

  defp details(%{stripe_subscription_id: subscription_id}) do
    with {:ok, %{"items" => %{"data" => [item]}} = stripe} <-
           StripeTerms.request(:get, "/v1/subscriptions/#{subscription_id}"),
         {:ok, {plan, billing_period}} <- plan_and_period(item) do
      {:ok,
       %{
         plan: plan,
         billing_period: billing_period,
         amount: StripeTerms.pln(item["price"]["unit_amount"]),
         current_period_end: StripeTerms.warsaw_date(item["current_period_end"]),
         # Stripe ends the subscription at the end of the current period either by setting
         # `cancel_at_period_end` or by a `cancel_at` at that moment.
         cancel_at_period_end: stripe["cancel_at_period_end"] == true or not is_nil(stripe["cancel_at"]),
         trialing?: stripe["status"] == "trialing",
         payment_overdue?: stripe["status"] == "past_due"
       }}
    end
  end

  defp plan_and_period(item) do
    case StripeTerms.plan_of(item["price"]) do
      {:ok, plan_and_period} -> {:ok, plan_and_period}
      :error -> {:error, "The Stripe subscription's price is not a Firmowid plan"}
    end
  end
end
