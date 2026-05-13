defmodule Firmowid.Ash.Billing do
  @moduledoc """
  Ash domain for billing catalogs and monthly organization snapshots.
  """

  use Ash.Domain

  alias Firmowid.Ash.Billing.Snapshot

  resources do
    resource Snapshot do
      define :list_billing_snapshots, action: :read
      define :list_billing_snapshots_global, action: :read_global
      define :get_billing_snapshot, action: :read, get_by: [:id]
      define :get_billing_snapshot_for_month, action: :by_month, args: [:month]
      define :create_billing_snapshot, action: :create
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
