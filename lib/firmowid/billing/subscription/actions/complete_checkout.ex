defmodule Firmowid.Billing.Subscription.Actions.CompleteCheckout do
  @moduledoc """
  Syncs the subscription a returned Checkout Session created. Stripe's redirect does not prove
  the purchase; the session is read from Stripe, and its subscription is synced like every
  subscription event does, so the plan is on when the admin arrives.

  A session of another customer, or one without a subscription (not completed), changes nothing.
  """

  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Query.NotFound
  alias Firmowid.Billing.StripeEvents
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Billing.Subscription
  alias Firmowid.Core

  @doc "Syncs the session's subscription and returns whether it gives the plan."
  @spec run(Ash.ActionInput.t(), keyword(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, boolean()} | {:error, term()}
  @impl true
  def run(input, _opts, context) do
    session_id = Ash.ActionInput.get_argument(input, :session_id)

    with {:ok, organization} <-
           Core.get_organization(context.tenant, Ash.Context.to_opts(context)),
         {:ok, session} <- StripeTerms.request(:get, "/v1/checkout/sessions/#{session_id}"),
         :ok <- check_customer(session, organization) do
      case session["subscription"] do
        subscription_id when is_binary(subscription_id) -> sync(subscription_id)
        _not_completed -> {:ok, false}
      end
    end
  end

  defp check_customer(%{"customer" => customer}, %{stripe_customer_id: customer}), do: :ok

  defp check_customer(_session, _organization), do: {:error, NotFound.exception(resource: Subscription)}

  defp sync(subscription_id) do
    case StripeEvents.sync(subscription_id) do
      {:ok, %{stripe_subscription_id: ^subscription_id}} -> {:ok, true}
      {:ok, _other} -> {:ok, false}
      {:error, error} -> {:error, error}
    end
  end
end
