defmodule Firmowid.Ash.Ksef.Credential do
  @moduledoc """
  Ash resource for storing KSeF authentication credentials per organization.

  Credentials are stored encrypted and support both token-based and
  certificate-based authentication methods.

  Table: `ksef_credentials` (already exists, `migrate?: false`).
  No multitenancy — queried by explicit `organization_id` filter, not tenant.
  Added to `@unscoped_tables` in Repo.
  """

  use Ash.Resource,
    domain: Firmowid.Ash.Ksef,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.SystemActorRole

  postgres do
    table "ksef_credentials"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :create
    define :destroy
    define :get_by_organization, args: [:organization_id], action: :by_organization
    define :all_organization_ids, action: :all_organization_ids
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:organization_id, :auth_type, :credentials]
    end

    read :by_organization do
      argument :organization_id, :uuid, allow_nil?: false
      get? true
      filter expr(organization_id == ^arg(:organization_id))
    end

    read :all_organization_ids do
      prepare fn query, _context ->
        Ash.Query.select(query, [:organization_id])
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # ksef_session: all actions
    bypass {SystemActorRole, roles: [:ksef_session]} do
      authorize_if always()
    end

    # sales_invoice_processor: read
    bypass {SystemActorRole, roles: [:sales_invoice_processor]} do
      authorize_if action_type(:read)
    end

    # cross_tenant_reader: read (for all_organization_ids action)
    bypass {SystemActorRole, roles: [:cross_tenant_reader]} do
      authorize_if action_type(:read)
    end

    # Other actors: no access
    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :auth_type, :atom do
      constraints one_of: [:token, :certificate]
      allow_nil? false
      public? true
    end

    attribute :credentials, Firmowid.Ash.Ksef.EncryptedBinaryType do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_organization, [:organization_id]
  end
end
