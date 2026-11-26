defmodule Firmowid.Billing.Subscription do
  @moduledoc """
  The application's view of the organization's Stripe subscription.

  Stripe keeps the subscription: the card, every period's charge, prorated plan switches,
  retries of declined payments and the end of a trial. This resource is how the application
  starts one (`:start`), reads it (`:details`), manages it in Stripe's customer portal
  (`:open_portal`) and finds its customer in the Stripe Dashboard (`:open_dashboard`), where a
  superuser gives trials and cancels. The plan itself is on the
  organization (`Organization.billing_plan`), which `:follow_stripe_subscription` sets from
  Stripe's current state.

  The organization is always the tenant, so every action works on the organization the caller
  acts in.
  """

  use Ash.Resource,
    domain: Firmowid.Billing,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.Subscription.Actions.Checkout
  alias Firmowid.Billing.Subscription.Actions.CompleteCheckout
  alias Firmowid.Billing.Subscription.Actions.Details
  alias Firmowid.Billing.Subscription.Actions.OpenDashboard
  alias Firmowid.Billing.Subscription.Actions.OpenPortal
  alias Firmowid.Billing.Subscription.Actions.TrialAvailable
  alias Firmowid.Checks.ActorRole

  resource do
    require_primary_key? false
  end

  actions do
    action :start, :string do
      description "Open a Stripe Checkout Session for a paid plan and return its URL."
      argument :plan, :atom, allow_nil?: false, constraints: [one_of: PlanCatalog.paid_plans()]

      argument :billing_period, :atom,
        allow_nil?: false,
        constraints: [one_of: PlanCatalog.billing_periods()]

      argument :success_url, :string, allow_nil?: false
      argument :cancel_url, :string, allow_nil?: false
      run Checkout
    end

    action :complete_checkout, :boolean do
      description "Sync the subscription a returned Checkout Session created; true when it gives the plan."
      argument :session_id, :string, allow_nil?: false
      run CompleteCheckout
    end

    action :open_portal, :string do
      description "Open Stripe's customer portal (card, plan switch, cancellation) and return its URL."
      argument :return_url, :string, allow_nil?: false
      run OpenPortal
    end

    action :details, :map do
      description "Read the organization's subscription from Stripe; nil when it has none."
      allow_nil? true
      run Details
    end

    action :trial_available?, :boolean do
      description "Whether a purchase starts with the free 60 days: the organization never had a Stripe subscription."
      run TrialAvailable
    end

    action :open_dashboard, :string do
      description "Return the Stripe Dashboard URL of the organization's customer, creating the customer if needed."
      run OpenDashboard
    end
  end

  policies do
    policy action([:start, :complete_checkout, :open_portal, :details, :trial_available?]) do
      authorize_if {ActorRole, role: :admin}
    end

    policy action(:open_dashboard) do
      authorize_if actor_attribute_equals(:system_role, :superuser)
    end
  end
end
