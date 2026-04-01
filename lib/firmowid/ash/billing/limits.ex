defmodule Firmowid.Ash.Billing.Limits do
  @moduledoc """
  Tracks monthly usage of cost/sales invoices and total bank connections
  per organization. Invoice counts are reset by a cron job on the 1st of
  each month.

  Usage counts are stored as denormalized counters — O(1) reads, simple
  threshold checks, no cross-domain joins. Drift is acceptable for soft
  (informational) limits.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  @type limit_type :: :cost_invoices | :sales_invoices | :bank_connections

  postgres do
    table "organization_limits"
    repo Firmowid.Repo
    migrate? false
  end

  actions do
    defaults [:read]

    read :read_all do
      multitenancy :bypass
    end

    create :create do
      accept []
    end

    update :increment_counter do
      argument :type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:cost_invoices, :sales_invoices, :bank_connections]]

      change Firmowid.Ash.Billing.Changes.IncrementCounter
    end

    update :decrement_counter do
      argument :type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:cost_invoices, :sales_invoices, :bank_connections]]

      change Firmowid.Ash.Billing.Changes.DecrementCounter
    end

    update :reset_counters do
      multitenancy :bypass
      accept []

      change set_attribute(:cost_invoices_used, 0)
      change set_attribute(:sales_invoices_used, 0)
    end
  end

  policies do
    policy action_type([:read, :update]) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :organization_id, :uuid_v7, public?: true, allow_nil?: false

    attribute :cost_invoices_used, :integer, public?: true, default: 0
    attribute :cost_invoices_limit, :integer, public?: true, default: 100
    attribute :sales_invoices_used, :integer, public?: true, default: 0
    attribute :sales_invoices_limit, :integer, public?: true, default: 100
    attribute :bank_connections_used, :integer, public?: true, default: 0
    attribute :bank_connections_limit, :integer, public?: true, default: 5

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      define_attribute? false
      allow_nil? false
    end
  end

  identities do
    identity :unique_organization, [:organization_id]
  end
end
