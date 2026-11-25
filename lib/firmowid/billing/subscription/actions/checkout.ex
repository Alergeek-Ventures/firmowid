defmodule Firmowid.Billing.Subscription.Actions.Checkout do
  @moduledoc """
  Opens a Stripe Checkout Session for a paid plan: Stripe collects the card, the billing address
  and the tax id, and brings the buyer back to the `:success_url` argument (or to `:cancel_url`
  after a checkout left without completing it). Stripe's events find the organization through
  the customer.

  A purchase is refused for the organization that sells Firmowid (it has no Stripe customer), one
  that already pays and one whose plan was granted by hand. The first purchase starts with the
  free 30 days. A customer has one open session at a time: opening a checkout expires the one
  left open before, so two of them cannot both be paid into two subscriptions.

  The subscription carries the organization's id in its metadata, so its events find the
  organization even after its customer was deleted at Stripe.
  """

  use Ash.Resource.Actions.Implementation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Billing.Subscription.Actions.TrialAvailable
  alias Firmowid.Billing.Subscription.Customer
  alias Firmowid.Core

  @trial_days 30

  @doc "Opens the Checkout Session and returns its URL."
  @spec run(Ash.ActionInput.t(), keyword(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, String.t()} | {:error, term()}
  @impl true
  def run(input, _opts, context) do
    plan = Ash.ActionInput.get_argument(input, :plan)
    billing_period = Ash.ActionInput.get_argument(input, :billing_period)

    with {:ok, organization} <-
           Core.get_organization(
             context.tenant,
             Ash.Context.to_opts(context, load: [:plan_granted?, :owner])
           ),
         :ok <- check(organization),
         {:ok, customer_id} <- Customer.ensure(organization),
         {:ok, price} <- StripeTerms.price(plan, billing_period),
         {:ok, trial?} <- TrialAvailable.available?(organization),
         :ok <- expire_open_sessions(customer_id),
         {:ok, %{"url" => url}} <-
           StripeTerms.request(
             :post,
             "/v1/checkout/sessions",
             params(input, organization.id, customer_id, price, trial?)
           ) do
      {:ok, url}
    end
  end

  defp check(organization) do
    cond do
      is_binary(organization.stripe_subscription_id) ->
        refuse(gettext_noop("This company already pays for a plan. Change it in the subscription settings."))

      organization.plan_granted? ->
        refuse(gettext_noop("This company's plan was granted, so there is nothing to buy."))

      true ->
        :ok
    end
  end

  defp refuse(message), do: {:error, InvalidChanges.exception(message: message)}

  defp expire_open_sessions(customer_id) do
    with {:ok, %{"data" => sessions}} <-
           StripeTerms.request(:get, "/v1/checkout/sessions", %{
             customer: customer_id,
             status: :open
           }) do
      Enum.reduce_while(sessions, :ok, fn %{"id" => session_id}, :ok ->
        case StripeTerms.request(:post, "/v1/checkout/sessions/#{session_id}/expire") do
          {:ok, _expired} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  defp params(input, organization_id, customer_id, price, trial?) do
    trial = if trial?, do: %{trial_period_days: @trial_days}, else: %{}

    %{
      subscription_data: Map.put(trial, :metadata, %{organization_id: organization_id}),
      mode: :subscription,
      # Plans are priced and invoiced in PLN. Stripe's Adaptive Pricing would let a buyer abroad
      # pay in their own currency, and the advance invoice would follow it.
      adaptive_pricing: %{enabled: false},
      customer: customer_id,
      locale: :pl,
      payment_method_types: [:card],
      line_items: [%{price: price["id"], quantity: 1}],
      billing_address_collection: :required,
      tax_id_collection: %{enabled: true, required: :if_supported},
      customer_update: %{name: :auto, address: :auto},
      success_url: Ash.ActionInput.get_argument(input, :success_url),
      cancel_url: Ash.ActionInput.get_argument(input, :cancel_url)
    }
  end
end
