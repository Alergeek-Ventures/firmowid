defmodule Firmowid.Billing.StripeEvents do
  @moduledoc """
  Applies the Stripe events Firmowid listens to (as string-keyed maps).

  Every event about a subscription (`customer.subscription.created|updated|deleted`, which also
  cover a completed Checkout) reads the Stripe subscription again and makes the organization's
  plan follow its current state (`Organization :follow_stripe_subscription`), so a repeated or
  late event changes nothing. The organization comes from the metadata of the subscription, or
  of its customer, so a subscription a superuser creates in the Stripe Dashboard is followed like
  one bought in Checkout; an organization this environment does not know (another environment
  sharing the Stripe account) is ignored.

  `invoice.paid` with an amount is read again and recorded by `Payment :record`, once per Stripe
  invoice, which issues its advance invoice. Every paid invoice of the Stripe account with an
  amount is remembered, whatever happens to the plan: the plan follows the subscription events,
  not the payment. An invoice for nothing (a trial's first invoice) is skipped. Stripe sends the
  emails about failed payments, ending trials and receipts.
  """

  alias Firmowid.Billing
  alias Firmowid.Billing.StripeTerms
  alias Firmowid.Core

  @subscription_events ~w(customer.subscription.created customer.subscription.updated customer.subscription.deleted)

  @doc "The event types a webhook endpoint of Firmowid listens to."
  @spec types() :: [String.t()]
  def types, do: @subscription_events ++ ["invoice.paid"]

  @doc "Applies a verified Stripe event."
  @spec handle(map()) :: :ok | {:error, term()}
  def handle(%{"type" => type, "data" => %{"object" => object}}) do
    case {type, object} do
      {type, %{"id" => stripe_id}} when type in @subscription_events ->
        ok(sync(stripe_id))

      {"invoice.paid", %{"id" => invoice_id}} ->
        ok(record_paid_invoice(invoice_id))

      _other ->
        :ok
    end
  end

  @doc """
  Makes the organization named in the metadata of the Stripe subscription's customer follow
  it, as Stripe reports it now. Returns the organization, or `:foreign` when this environment does not know it.
  """
  @spec sync(String.t()) :: {:ok, Firmowid.Core.Organization.t() | :foreign} | {:error, term()}
  def sync(stripe_id) do
    with {:ok, stripe} <-
           StripeTerms.request(:get, "/v1/subscriptions/#{stripe_id}", %{expand: ["customer"]}),
         # `{:ok, :foreign}` does not match and is returned as it is.
         {:ok, %{id: _id} = organization} <- organization(organization_id(stripe)) do
      Core.follow_organization_stripe_subscription(
        organization,
        stripe,
        scope: Billing.scope(organization.id)
      )
    end
  end

  # A subscription bought in Checkout names its organization itself, which a customer deleted at
  # Stripe no longer does; one created in the Stripe Dashboard is found through its customer.
  defp organization_id(stripe) do
    stripe["metadata"]["organization_id"] || stripe["customer"]["metadata"]["organization_id"]
  end

  defp organization(nil), do: {:ok, :foreign}

  defp organization(org_id) do
    case Core.get_organization(org_id, scope: Billing.scope(org_id), not_found_error?: false) do
      {:ok, nil} -> {:ok, :foreign}
      {:ok, organization} -> {:ok, organization}
      {:error, error} -> {:error, error}
    end
  end

  # Records a paid invoice as a payment, once per invoice. The paid invoice is read again, like
  # the subscription: an event is shaped by the API version of the webhook endpoint (set in the
  # Stripe Dashboard), a request by the one the Stripe library pins, so only a request gives the
  # paid invoice a shape this code can rely on.
  defp record_paid_invoice(invoice_id) do
    with {:ok, invoice} <- StripeTerms.request(:get, "/v1/invoices/#{invoice_id}") do
      record(invoice)
    end
  end

  defp record(%{"amount_paid" => amount} = invoice) when amount > 0 do
    Billing.record_payment(
      %{stripe_invoice_id: invoice["id"]},
      scope: Billing.scope(Billing.seller_organization_id())
    )
  end

  # An invoice for nothing (a trial's first invoice).
  defp record(_invoice), do: {:ok, nil}

  defp ok({:ok, _result}), do: :ok
  defp ok({:error, error}), do: {:error, error}
end
