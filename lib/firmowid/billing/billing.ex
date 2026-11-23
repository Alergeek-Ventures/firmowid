defmodule Firmowid.Billing do
  @moduledoc """
  Ash domain for billing catalogs, monthly organization snapshots, the subscriptions
  organizations buy through Stripe and the payments Stripe took for them.
  """

  use Ash.Domain

  alias Firmowid.Billing.Payment
  alias Firmowid.Billing.Snapshot
  alias Firmowid.Billing.Subscription
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  resources do
    resource Snapshot do
      define :list_billing_snapshots_global, action: :read_global
      define :get_billing_snapshot, action: :read, get_by: [:id]
      define :get_billing_snapshot_for_month, action: :by_month, args: [:month]
      define :create_billing_snapshot, action: :create
    end

    resource Subscription do
      define :start_subscription, action: :start
      define :complete_subscription_checkout, action: :complete_checkout, args: [:session_id]
      define :open_subscription_portal, action: :open_portal
      define :get_subscription_details, action: :details
      define :subscription_trial_available?, action: :trial_available?
      define :open_subscription_dashboard, action: :open_dashboard
    end

    resource Payment do
      define :record_payment, action: :record
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Returns the scope of the `:billing` system actor, which applies Stripe's events to the
  subscriptions and payments of `organization_id`.
  """
  @spec scope(Ash.UUID.t()) :: Scope.t()
  def scope(organization_id) do
    Scope.new!(%SystemActor{org_id: organization_id, role: :billing}, organization_id)
  end

  @doc """
  Returns the id of the organization that sells Firmowid: it issues the advance invoices of
  the payments and cannot buy a plan itself.
  """
  @spec seller_organization_id() :: Ash.UUID.t()
  def seller_organization_id do
    :firmowid |> Application.fetch_env!(:billing) |> Keyword.fetch!(:seller_organization_id)
  end
end
