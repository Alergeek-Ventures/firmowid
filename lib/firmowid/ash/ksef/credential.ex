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
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ksef_credentials"
    repo Firmowid.Repo
    migrate? false
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
