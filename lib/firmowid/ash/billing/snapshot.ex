defmodule Firmowid.Ash.Billing.Snapshot do
  @moduledoc """
  Monthly frozen usage facts for organization billing.
  """

  use Ash.Resource,
    domain: Firmowid.Ash.Billing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Billing.PlanCatalog
  alias Firmowid.Ash.Checks.IsSystemActor
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "billing_snapshots"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :read_global, action: :read_global
    define :by_month, args: [:month], action: :by_month
    define :create, action: :create
  end

  actions do
    defaults [:read]

    read :by_month do
      get? true
      argument :month, :date, allow_nil?: false
      filter expr(month == ^arg(:month))
    end

    read :read_global do
      multitenancy :allow_global

      pagination do
        required? false
        keyset? true
      end
    end

    create :create do
      accept [
        :month,
        :billing_plan,
        :manual_external_invoices_count,
        :synced_bank_accounts_count,
        :active_non_owner_users_count,
        :frozen_at
      ]
    end
  end

  policies do
    bypass {SystemActorRole, roles: [:billing_snapshotter]} do
      authorize_if action_type([:read, :create])
    end

    policy IsSystemActor do
      forbid_if always()
    end

    policy action(:read_global) do
      authorize_if actor_attribute_equals(:system_role, :superuser)
    end

    policy action([:read, :by_month]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :month, :date, public?: true, allow_nil?: false

    attribute :billing_plan, :atom,
      public?: true,
      allow_nil?: false,
      default: :przedsiebiorca,
      constraints: [one_of: PlanCatalog.plans()]

    attribute :manual_external_invoices_count, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :synced_bank_accounts_count, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :active_non_owner_users_count, :integer,
      public?: true,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0]

    attribute :frozen_at, :utc_datetime_usec, public?: true, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_month_per_organization, [:organization_id, :month]
  end
end
