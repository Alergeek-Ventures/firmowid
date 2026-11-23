defmodule FirmowidWeb.Billing.Controllers.CheckoutReturnTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.BillingFixtures

  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core

  # The sessions are opened in the Stripe sandbox. Only a browser can pay one, so the return
  # from a paid session is checked by hand (`mix stripe.listen` and a test card).
  @moduletag :external

  setup %{conn: conn} do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    customer_id = stripe_customer!(org_id)

    org_id
    |> organization()
    |> Ash.Seed.update!(%{stripe_customer_id: customer_id})

    %{conn: log_in_user(conn, admin), org_id: org_id, customer_id: customer_id}
  end

  test "a session the organization's customer has not paid changes nothing", %{
    conn: conn,
    org_id: org_id,
    customer_id: customer_id
  } do
    conn = get(conn, ~p"/abonament/powrot?sesja=#{checkout_session!(customer_id)}")

    assert redirected_to(conn) == ~p"/limit-planu"
    assert Phoenix.Flash.get(conn.assigns.flash, :info)
    assert organization(org_id).billing_plan == :free
  end

  test "a session of another customer is refused and changes nothing", %{
    conn: conn,
    org_id: org_id
  } do
    session_id = Ecto.UUID.generate() |> stripe_customer!() |> checkout_session!()

    conn = get(conn, ~p"/abonament/powrot?sesja=#{session_id}")

    assert redirected_to(conn) == ~p"/limit-planu"
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
    assert organization(org_id).billing_plan == :free
  end

  defp checkout_session!(customer_id) do
    {:ok, %{"id" => price_id}} = StripeTerms.price(:firma, :monthly)

    {:ok, %{"id" => session_id}} =
      StripeTerms.request(:post, "/v1/checkout/sessions", %{
        mode: :subscription,
        customer: customer_id,
        line_items: [%{price: price_id, quantity: 1}],
        success_url: "https://app.test/abonament/powrot",
        cancel_url: "https://app.test/limit-planu"
      })

    session_id
  end

  defp organization(org_id), do: Core.get_organization!(org_id, authorize?: false)
end
