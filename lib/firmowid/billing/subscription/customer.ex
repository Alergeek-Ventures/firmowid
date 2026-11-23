defmodule Firmowid.Billing.Subscription.Customer do
  @moduledoc """
  The organization's customer at Stripe: the one it already has, or a new one created from the
  organization's details. Stripe Checkout shows the address and the tax id as suggestions the
  buyer can correct.

  The organization that sells Firmowid gets no customer: it would pay itself and issue the
  advance invoice to itself. Without a customer nothing at Stripe can name it, neither a
  checkout nor a subscription created in the Stripe Dashboard.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges
  alias Firmowid.Billing
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core

  @doc "Returns the organization's Stripe customer, creating it when it has none."
  @spec ensure(Firmowid.Core.Organization.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure(%{stripe_customer_id: customer_id}) when is_binary(customer_id), do: {:ok, customer_id}

  def ensure(organization) do
    if organization.id == Billing.seller_organization_id() do
      {:error, InvalidChanges.exception(message: gettext_noop("The company that sells Firmowid cannot buy a plan."))}
    else
      create(organization)
    end
  end

  defp create(organization) do
    with {:ok, %{"id" => customer_id}} <-
           StripeTerms.request(:post, "/v1/customers", params(organization),
             idempotency_key: "firmowid-customer-#{organization.id}"
           ),
         {:ok, _organization} <-
           Core.link_organization_stripe_customer(
             organization,
             %{stripe_customer_id: customer_id},
             scope: Billing.scope(organization.id)
           ) do
      {:ok, customer_id}
    end
  end

  defp params(organization) do
    Map.merge(
      %{
        name: organization.name,
        # Checkout fills the company name of the tax details from it.
        business_name: organization.name,
        email: to_string(organization.owner.email),
        preferred_locales: ["pl"],
        metadata: %{organization_id: organization.id},
        tax_id_data: [%{type: :eu_vat, value: "PL" <> organization.nip}]
      },
      address(organization.address)
    )
  end

  defp address(nil), do: %{}
  defp address(""), do: %{}

  defp address(address) do
    case Regex.run(~r/^(.+),\s*(\d{2}-\d{3})\s+(.+)$/u, address) do
      [_, line1, postal_code, city] ->
        %{address: %{line1: line1, postal_code: postal_code, city: city, country: "PL"}}

      nil ->
        %{address: %{line1: address, country: "PL"}}
    end
  end
end
