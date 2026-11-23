defmodule Firmowid.Billing.SubscriptionTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.BillingFixtures

  alias Ash.Error.Changes.InvalidChanges
  alias Firmowid.Billing
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Billing.Subscription.Customer
  alias Firmowid.Core
  alias Firmowid.Scope

  # The tests tagged `:external` call the Stripe sandbox.

  @checkout_urls %{
    success_url: "https://app.test/abonament/powrot?sesja={CHECKOUT_SESSION_ID}",
    cancel_url: "https://app.test/limit-planu"
  }

  setup do
    admin = admin_fixture()
    org_id = admin.member.organization_id

    org_id
    |> organization()
    |> Ash.Seed.update!(%{name: "Acme Sp. z o.o.", address: "ul. Przykładowa 1, 00-001 Warszawa"})

    %{admin: admin, org_id: org_id, scope: %Scope{actor: admin, tenant: org_id}}
  end

  describe "purchase" do
    @tag :external
    test "creates the customer from the organization and opens a checkout with a 30-day trial",
         %{admin: admin, org_id: org_id, scope: scope} do
      assert {:ok, "https://checkout.stripe.com/" <> _path} =
               Billing.start_subscription(
                 Map.merge(%{plan: :firma, billing_period: :monthly}, @checkout_urls),
                 scope: scope
               )

      organization = organization(org_id)
      delete_stripe_customer_on_exit(organization.stripe_customer_id)

      assert {:ok,
              %{
                "name" => "Acme Sp. z o.o.",
                "email" => email,
                "metadata" => %{"organization_id" => ^org_id},
                "tax_ids" => %{"data" => [%{"type" => "eu_vat", "value" => "PL" <> nip}]},
                "address" => %{
                  "line1" => "ul. Przykładowa 1",
                  "postal_code" => "00-001",
                  "city" => "Warszawa",
                  "country" => "PL"
                }
              }} =
               StripeTerms.request(
                 :get,
                 "/v1/customers/#{organization.stripe_customer_id}",
                 %{expand: ["tax_ids"]}
               )

      assert email == to_string(admin.email)
      assert nip == organization.nip

      assert %{
               "mode" => "subscription",
               "locale" => "pl",
               "billing_address_collection" => "required",
               "tax_id_collection" => %{"enabled" => true, "required" => "if_supported"},
               "line_items" => %{
                 "data" => [
                   %{"price" => %{"lookup_key" => "firmowid_firma_monthly"}, "quantity" => 1}
                 ]
               },
               # Nothing is due on the day of the purchase: the trial.
               "amount_total" => 0
             } = checkout_session(organization.stripe_customer_id)
    end

    @tag :external
    test "after an earlier subscription opens a checkout without a trial, for the same customer",
         %{org_id: org_id, scope: scope} do
      customer_id = stripe_customer!(org_id)

      org_id
      |> organization()
      |> Ash.Seed.update!(%{stripe_customer_id: customer_id})

      %{"id" => earlier} = stripe_subscription!(customer_id, :firma, %{trial_period_days: 30})
      cancel_stripe_subscription!(earlier)

      assert {:ok, "https://checkout.stripe.com/" <> _path} =
               Billing.start_subscription(
                 Map.merge(%{plan: :przedsiebiorca, billing_period: :yearly}, @checkout_urls),
                 scope: scope
               )

      assert organization(org_id).stripe_customer_id == customer_id

      # The whole price is due on the day of the purchase.
      {:ok, %{"unit_amount" => yearly_price}} = StripeTerms.price(:przedsiebiorca, :yearly)
      assert %{"amount_total" => ^yearly_price} = checkout_session(customer_id)
    end

    @tag :external
    test "opening another checkout expires the one left open", %{org_id: org_id, scope: scope} do
      for billing_period <- [:monthly, :yearly] do
        assert {:ok, _url} =
                 Billing.start_subscription(
                   Map.merge(%{plan: :firma, billing_period: billing_period}, @checkout_urls),
                   scope: scope
                 )
      end

      customer_id = organization(org_id).stripe_customer_id
      delete_stripe_customer_on_exit(customer_id)

      {:ok, %{"data" => sessions}} =
        StripeTerms.request(:get, "/v1/checkout/sessions", %{customer: customer_id})

      assert sessions |> Enum.map(& &1["status"]) |> Enum.sort() == ["expired", "open"]
    end

    test "the company that sells Firmowid gets no Stripe customer, before Stripe is called", %{
      org_id: org_id
    } do
      seller = %{organization(org_id) | id: Billing.seller_organization_id()}

      assert {:error, %InvalidChanges{message: "The company that sells Firmowid cannot buy a plan."}} =
               Customer.ensure(seller)
    end

    test "is refused for an organization that already pays, before Stripe is called", %{
      org_id: org_id,
      scope: scope
    } do
      subscribed!(org_id)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Billing.start_subscription(
                 Map.merge(%{plan: :firma, billing_period: :monthly}, @checkout_urls),
                 scope: scope
               )

      assert Exception.message(error) =~ "already pays for a plan"
    end
  end

  describe "a plan set by hand" do
    @describetag :external

    setup %{admin: admin, org_id: org_id} do
      customer_id = stripe_customer!(org_id)

      %{"id" => subscription_id} =
        stripe_subscription!(customer_id, :przedsiebiorca, %{trial_period_days: 30})

      subscribed!(org_id, %{
        stripe_customer_id: customer_id,
        stripe_subscription_id: subscription_id
      })

      %{superuser: %{admin | system_role: :superuser}, subscription_id: subscription_id}
    end

    test "cancels the Stripe subscription the organization has now and forgets it", %{
      org_id: org_id,
      superuser: superuser,
      subscription_id: subscription_id
    } do
      # The record a page opened before the purchase still holds.
      opened_before_purchase = %{organization(org_id) | stripe_subscription_id: nil}

      assert {:ok, organization} =
               Core.update_organization_billing_plan(
                 opened_before_purchase,
                 %{billing_plan: :firma},
                 actor: superuser
               )

      assert organization.billing_plan == :firma
      assert organization.stripe_subscription_id == nil

      assert {:ok, %{"status" => "canceled"}} =
               StripeTerms.request(:get, "/v1/subscriptions/#{subscription_id}")
    end

    test "forgets a subscription Stripe has already cancelled", %{
      org_id: org_id,
      superuser: superuser,
      subscription_id: subscription_id
    } do
      cancel_stripe_subscription!(subscription_id)

      assert {:ok, organization} =
               Core.update_organization_billing_plan(
                 organization(org_id),
                 %{billing_plan: :free},
                 actor: superuser
               )

      assert organization.billing_plan == :free
      assert organization.stripe_subscription_id == nil
    end
  end

  # The Checkout Session a purchase opened for the customer, as Stripe holds it.
  defp checkout_session(customer_id) do
    {:ok, %{"data" => [session]}} =
      StripeTerms.request(:get, "/v1/checkout/sessions", %{
        customer: customer_id,
        expand: ["data.line_items"]
      })

    session
  end

  defp organization(org_id), do: Core.get_organization!(org_id, authorize?: false)
end
