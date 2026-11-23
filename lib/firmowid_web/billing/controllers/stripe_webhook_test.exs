defmodule FirmowidWeb.Billing.Controllers.StripeWebhookTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.BillingFixtures

  alias Firmowid.Billing
  alias Firmowid.Billing.Payment
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core
  alias Firmowid.Core.Organization

  test "an event without a valid signature is rejected", %{conn: conn} do
    body = event("customer.subscription.deleted", "sub_1")

    conn = post_signed(conn, body, "t=#{System.system_time(:second)},v1=forged")

    assert response(conn, 400)
  end

  # The events are built and signed here, as Stripe would send them, about subscriptions and
  # invoices that exist in the Stripe sandbox: the app reads them from there.
  describe "an event about the Stripe sandbox" do
    @describetag :external

    test "a live subscription sets the organization's plan and subscription id, however often it arrives",
         %{conn: conn} do
      org_id = admin_fixture().member.organization_id
      customer_id = stripe_customer!(org_id)

      %{"id" => subscription_id} =
        stripe_subscription!(customer_id, :firma, %{trial_period_days: 30})

      assert conn |> post_event("customer.subscription.created", subscription_id) |> response(200)

      assert build_conn()
             |> post_event("customer.subscription.created", subscription_id)
             |> response(200)

      organization = organization(org_id)
      assert organization.billing_plan == :firma
      assert organization.stripe_subscription_id == subscription_id
      assert organization.stripe_customer_id == customer_id
    end

    test "a canceled subscription returns the organization to Free and clears the id", %{
      conn: conn
    } do
      org_id = admin_fixture().member.organization_id
      customer_id = stripe_customer!(org_id)

      %{"id" => subscription_id} =
        stripe_subscription!(customer_id, :firma, %{trial_period_days: 30})

      subscribed!(org_id, %{
        stripe_customer_id: customer_id,
        stripe_subscription_id: subscription_id
      })

      cancel_stripe_subscription!(subscription_id)

      assert conn |> post_event("customer.subscription.deleted", subscription_id) |> response(200)

      organization = organization(org_id)
      assert organization.billing_plan == :free
      assert organization.stripe_subscription_id == nil
    end

    test "a subscription whose customer was deleted at Stripe returns the organization to Free",
         %{
           conn: conn
         } do
      org_id = admin_fixture().member.organization_id
      customer_id = stripe_customer!(org_id)

      # A subscription bought in Checkout names its organization itself.
      %{"id" => subscription_id} =
        stripe_subscription!(customer_id, :firma, %{
          trial_period_days: 30,
          metadata: %{organization_id: org_id}
        })

      subscribed!(org_id, %{
        stripe_customer_id: customer_id,
        stripe_subscription_id: subscription_id
      })

      {:ok, %{"deleted" => true}} = StripeTerms.request(:delete, "/v1/customers/#{customer_id}")

      assert conn |> post_event("customer.subscription.deleted", subscription_id) |> response(200)

      organization = organization(org_id)
      assert organization.billing_plan == :free
      assert organization.stripe_subscription_id == nil
      assert organization.stripe_customer_id == nil
    end

    test "a subscription that is over and is not the organization's changes nothing", %{
      conn: conn
    } do
      org_id = admin_fixture().member.organization_id
      customer_id = stripe_customer!(org_id)
      %{"id" => other} = stripe_subscription!(customer_id, :firma, %{trial_period_days: 30})
      subscribed!(org_id, %{stripe_customer_id: customer_id, stripe_subscription_id: "sub_mine"})
      cancel_stripe_subscription!(other)

      assert conn |> post_event("customer.subscription.deleted", other) |> response(200)

      organization = organization(org_id)
      assert organization.billing_plan == :przedsiebiorca
      assert organization.stripe_subscription_id == "sub_mine"
    end

    test "an incomplete subscription changes nothing", %{conn: conn} do
      org_id = admin_fixture().member.organization_id

      %{"id" => subscription_id, "status" => "incomplete"} =
        org_id
        |> stripe_customer!()
        |> stripe_subscription!(:firma, %{payment_behavior: :default_incomplete})

      assert conn |> post_event("customer.subscription.created", subscription_id) |> response(200)

      organization = organization(org_id)
      assert organization.billing_plan == :free
      assert organization.stripe_subscription_id == nil
    end

    test "a subscription of an organization this environment does not know is ignored", %{
      conn: conn
    } do
      %{"id" => subscription_id} =
        Ecto.UUID.generate()
        |> stripe_customer!()
        |> stripe_subscription!(:firma, %{trial_period_days: 30})

      assert conn |> post_event("customer.subscription.created", subscription_id) |> response(200)
    end

    test "a paid invoice is remembered once for the seller, however often it arrives", %{
      conn: conn
    } do
      seller_id = Billing.seller_organization_id()

      Ash.Seed.seed!(Organization, %{
        id: seller_id,
        name: "Firmowid Sp. z o.o.",
        display_name: "Firmowid",
        nip: unique_nip(),
        owner_id: user_fixture().id
      })

      %{"latest_invoice" => invoice_id} =
        Ecto.UUID.generate() |> stripe_customer!() |> stripe_subscription!(:przedsiebiorca)

      assert conn |> post_event("invoice.paid", invoice_id) |> response(200)
      assert build_conn() |> post_event("invoice.paid", invoice_id) |> response(200)

      assert [%{stripe_invoice_id: ^invoice_id, invoiced_at: nil}] =
               Payment.list!(%{}, scope: Billing.scope(seller_id), authorize?: false)
    end
  end

  defp post_event(conn, type, stripe_id) do
    body = event(type, stripe_id)
    post_signed(conn, body, signature(body))
  end

  defp post_signed(conn, body, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature)
    |> post(~p"/webhooks/stripe", body)
  end

  # The app reads only the type and the object's id from an event, and the rest from Stripe.
  defp event(type, stripe_id) do
    Jason.encode!(%{
      "id" => "evt_test_#{System.unique_integer([:positive])}",
      "object" => "event",
      "type" => type,
      "data" => %{"object" => %{"id" => stripe_id}}
    })
  end

  # Signs a body with the endpoint's secret, as Stripe does (https://docs.stripe.com/webhooks#verify-manually).
  defp signature(body) do
    secret = :firmowid |> Application.fetch_env!(:stripe) |> Keyword.fetch!(:webhook_secret)
    timestamp = System.system_time(:second)

    digest =
      :hmac
      |> :crypto.mac(:sha256, secret, "#{timestamp}.#{body}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{digest}"
  end

  defp organization(org_id), do: Core.get_organization!(org_id, authorize?: false)
end
