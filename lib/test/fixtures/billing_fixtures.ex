defmodule Firmowid.BillingFixtures do
  @moduledoc """
  Test helpers for Stripe subscriptions: a subscription that exists only in the test database,
  for tests that never reach Stripe, and customers and subscriptions in the Stripe sandbox for
  the tests tagged `:external` (`mix test --include external`, with the sandbox key of
  Infisical dev).
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core

  @doc """
  Gives the organization a paid Przedsiębiorca plan with a unique Stripe subscription (customer
  `cus_test`), unless `attrs` say otherwise, and returns the organization.
  """
  @spec subscribed!(Ecto.UUID.t(), map()) :: Firmowid.Core.Organization.t()
  def subscribed!(organization_id, attrs \\ %{}) do
    organization_id
    |> Core.get_organization!(authorize?: false)
    |> Ash.Seed.update!(
      Map.merge(
        %{
          billing_plan: :przedsiebiorca,
          stripe_customer_id: "cus_test",
          stripe_subscription_id: "sub_test_#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
  end

  @doc """
  Creates the organization's customer in the Stripe sandbox, a company with a tax id, an address
  and a test card that pays, and returns its id. Stripe deletes the customer and cancels its
  subscriptions when the test ends.
  """
  @spec stripe_customer!(Ecto.UUID.t()) :: String.t()
  def stripe_customer!(organization_id) do
    {:ok, %{"id" => customer_id}} =
      StripeTerms.request(:post, "/v1/customers", %{
        name: "Acme Sp. z o.o.",
        email: "jan.kowalski@example.com",
        preferred_locales: ["pl"],
        metadata: %{organization_id: organization_id},
        tax_id_data: [%{type: :eu_vat, value: "PL1111111111"}],
        address: %{
          line1: "ul. Przykładowa 1",
          postal_code: "00-001",
          city: "Warszawa",
          country: "PL"
        },
        payment_method: "pm_card_visa",
        invoice_settings: %{default_payment_method: "pm_card_visa"}
      })

    delete_stripe_customer_on_exit(customer_id)
    customer_id
  end

  @doc "Deletes a sandbox customer, with its subscriptions, when the test ends."
  @spec delete_stripe_customer_on_exit(String.t()) :: :ok
  def delete_stripe_customer_on_exit(customer_id) do
    on_exit(fn -> StripeTerms.request(:delete, "/v1/customers/#{customer_id}") end)
  end

  @doc """
  Subscribes a sandbox customer to a plan's monthly price and returns the subscription as Stripe
  reports it. The test card pays the first invoice at once, so the subscription is `active`,
  unless `params` say otherwise: `%{trial_period_days: 30}` makes it `trialing` and
  `%{payment_behavior: :default_incomplete}` leaves it `incomplete`.
  """
  @spec stripe_subscription!(String.t(), PlanCatalog.offered_plan(), map()) :: map()
  def stripe_subscription!(customer_id, plan, params \\ %{}) do
    {:ok, price} = StripeTerms.price(plan, :monthly)

    {:ok, subscription} =
      StripeTerms.request(
        :post,
        "/v1/subscriptions",
        Map.merge(%{customer: customer_id, items: [%{price: price["id"]}]}, params)
      )

    subscription
  end

  @doc "Cancels a sandbox subscription at once."
  @spec cancel_stripe_subscription!(String.t()) :: :ok
  def cancel_stripe_subscription!(subscription_id) do
    {:ok, %{"status" => "canceled"}} =
      StripeTerms.request(:delete, "/v1/subscriptions/#{subscription_id}")

    :ok
  end
end
