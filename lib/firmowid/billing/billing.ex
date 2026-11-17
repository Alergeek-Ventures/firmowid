defmodule Firmowid.Billing do
  @moduledoc """
  Ash domain for billing catalogs, monthly organization snapshots, the subscriptions
  organizations buy with a card and the payments that charge it.
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

      define :get_subscription_by_tokenization_id,
        action: :by_tokenization_id,
        args: [:tokenization_id]

      define :save_subscription_card, action: :save_card
      define :change_subscription_card, action: :change_card
      define :upgrade_subscription, action: :upgrade, args: [:plan]
      define :switch_subscription_plan, action: :switch_plan
      define :end_subscription, action: :end
      define :list_subscriptions, action: :list
    end

    resource Payment do
      define :create_payment, action: :create
      define :charge_payment, action: :charge
      define :release_payment, action: :release
      define :record_payment_outcome, action: :record_outcome
      define :get_payment_global, action: :by_id_global, args: [:id]
      define :list_payments, action: :list
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Returns the scope of the `:billing` system actor, which charges, ends and switches the
  subscriptions of `organization_id`. Without an organization (`nil`) it can only look a
  record up across tenants.
  """
  @spec scope(Ash.UUID.t() | nil) :: Scope.t()
  def scope(organization_id) do
    Scope.new!(%SystemActor{org_id: organization_id, role: :billing}, organization_id)
  end
end
