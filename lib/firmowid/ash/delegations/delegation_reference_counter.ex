defmodule Firmowid.Ash.Delegations.DelegationReferenceCounter do
  @moduledoc """
  Atomically allocates delegation reference numbers within an organization,
  calendar month, and employee-initials namespace.
  """

  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Ash.Delegations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "delegation_reference_counters"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :next, action: :next
  end

  actions do
    defaults [:read]

    create :next do
      description "Allocate the next reference number for a delegation namespace."
      accept [:billing_month, :initials]
      upsert? true
      upsert_identity :unique_reference_namespace
      change set_attribute(:last_number, 1)
      change atomic_update(:last_number, expr(last_number + 1))
    end
  end

  policies do
    policy action(:next) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :billing_month, :date, allow_nil?: false
    attribute :initials, :string, allow_nil?: false
    attribute :last_number, :integer, allow_nil?: false, constraints: [min: 1]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_reference_namespace, [:organization_id, :billing_month, :initials]
  end
end
