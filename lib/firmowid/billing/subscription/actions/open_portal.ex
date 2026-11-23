defmodule Firmowid.Billing.Subscription.Actions.OpenPortal do
  @moduledoc """
  Opens a Stripe customer portal session (in Polish) for the organization's customer and returns
  its URL. The portal's default configuration decides what it offers: card changes, plan switches
  between Firmowid's prices (prorated by Stripe) and cancelling at the end of the period, without
  invoice history.

  Afterwards Stripe returns the admin to the `:return_url` argument; what changed reaches
  Firmowid through Stripe's events.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core

  @doc "Creates the portal session and returns its URL."
  @spec run(Ash.ActionInput.t(), keyword(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, String.t()} | {:error, term()}
  @impl true
  def run(input, _opts, context) do
    return_url = Ash.ActionInput.get_argument(input, :return_url)

    with {:ok, organization} <-
           Core.get_organization(context.tenant, Ash.Context.to_opts(context)),
         {:ok, customer_id} <- customer_id(organization),
         {:ok, %{"url" => url}} <-
           StripeTerms.request(:post, "/v1/billing_portal/sessions", %{
             customer: customer_id,
             locale: :pl,
             return_url: return_url
           }) do
      {:ok, url}
    end
  end

  defp customer_id(%{stripe_customer_id: customer_id}) when is_binary(customer_id), do: {:ok, customer_id}

  defp customer_id(_organization), do: {:error, "The organization has no Stripe customer"}
end
