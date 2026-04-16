defmodule Firmowid.Ash.Invoicing.KsefInvoiceDigestItem do
  @moduledoc """
  Join resource assigning KSeF cost invoices to exactly one digest.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Invoicing.Changes.SetOrganizationIdFromTenant
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "ksef_invoice_digest_items"
    repo Firmowid.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:digest_id, :cost_invoice_id]
      change SetOrganizationIdFromTenant
    end
  end

  policies do
    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:ksef_digest]} do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if {Firmowid.Ash.Checks.AtLeastRole, role: :accountant}
    end

    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :digest_id, :uuid, allow_nil?: false, public?: true
    attribute :cost_invoice_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :digest, Firmowid.Ash.Invoicing.KsefInvoiceDigest do
      attribute_writable? true
      define_attribute? false
      source_attribute :digest_id
      allow_nil? false
    end

    belongs_to :cost_invoice, Firmowid.Ash.Invoicing.CostInvoice do
      attribute_writable? true
      define_attribute? false
      source_attribute :cost_invoice_id
      allow_nil? false
    end
  end

  identities do
    identity :unique_cost_invoice, [:cost_invoice_id]
  end
end
