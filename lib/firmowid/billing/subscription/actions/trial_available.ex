defmodule Firmowid.Billing.Subscription.Actions.TrialAvailable do
  @moduledoc """
  Whether a purchase starts with the free 60 days: the organization never had a Stripe
  subscription. An organization without a Stripe customer never had one; otherwise Stripe is
  asked for any subscription of the customer.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core

  @doc "Returns whether the organization's purchase starts with the free 60 days."
  @spec run(Ash.ActionInput.t(), keyword(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, boolean()} | {:error, term()}
  @impl true
  def run(_input, _opts, context) do
    with {:ok, organization} <-
           Core.get_organization(context.tenant, Ash.Context.to_opts(context)) do
      available?(organization)
    end
  end

  @doc "Whether the organization never had a Stripe subscription."
  @spec available?(Firmowid.Core.Organization.t()) :: {:ok, boolean()} | {:error, term()}
  def available?(%{stripe_customer_id: nil}), do: {:ok, true}

  def available?(%{stripe_customer_id: customer_id}) do
    case StripeTerms.request(:get, "/v1/subscriptions", %{
           customer: customer_id,
           status: :all,
           limit: 1
         }) do
      {:ok, %{"data" => []}} -> {:ok, true}
      {:ok, %{"data" => [_subscription | _rest]}} -> {:ok, false}
      {:error, error} -> {:error, error}
    end
  end
end
