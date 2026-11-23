defmodule Firmowid.Billing.Subscription.Actions.OpenDashboard do
  @moduledoc """
  Returns the page of the organization's customer in the Stripe Dashboard, creating the customer
  when the organization has none.

  A superuser gives a trial, extends it, discounts or cancels a subscription there. A
  subscription created or changed in the Dashboard reaches Firmowid through Stripe's events,
  like one bought in Checkout.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Billing.Subscription.Customer
  alias Firmowid.Core

  @doc "Returns the Stripe Dashboard URL of the organization's customer."
  @spec run(Ash.ActionInput.t(), keyword(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, String.t()} | {:error, term()}
  @impl true
  def run(_input, _opts, context) do
    with {:ok, organization} <-
           Core.get_organization(context.tenant, Ash.Context.to_opts(context, load: [:owner])),
         {:ok, customer_id} <- Customer.ensure(organization) do
      {:ok, "https://dashboard.stripe.com/#{mode()}customers/#{customer_id}"}
    end
  end

  # The Dashboard keeps test data under its own path.
  defp mode do
    if String.contains?(Application.fetch_env!(:stripity_stripe, :api_key), "_test_"),
      do: "test/",
      else: ""
  end
end
