defmodule Firmowid.Ash.Finances.BankAccount do
  @moduledoc """
  Bank accounts synced from GoCardless or created manually.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "bank_accounts"
    repo Firmowid.Repo
    migrate? false

    # Maps the logical identity name to the pre-existing partial unique index name
    # created in migration 20250117142507_add_default_bank_accounts.exs.
    # Without this, AshPostgres would look for `bank_accounts_unique_default_per_currency_index`
    # and fail to convert Ecto.ConstraintError → Ash.Error.Invalid.
    identity_index_names unique_default_per_currency: "bank_accounts_organization_id_currency_is_default_index"
  end

  actions do
    defaults [:read, :destroy]

    create :sync_from_bank do
      # :name is accepted for initial insert but not in upsert_fields —
      # on conflict, user-set name is preserved.
      accept [
        :iban,
        :gocardless_id,
        :institution_id,
        :institution_name,
        :owner_name,
        :currency,
        :name,
        :requisition_id
      ]

      upsert? true
      upsert_identity :unique_iban_per_org

      upsert_fields [
        :gocardless_id,
        :institution_id,
        :institution_name,
        :owner_name,
        :currency,
        :requisition_id
      ]
    end

    create :create_manual do
      accept [:iban, :name, :currency, :is_default, :owner_name]

      change set_attribute(:institution_name, "Manual")
      change set_attribute(:gocardless_id, nil)
      change set_attribute(:institution_id, nil)
      change set_attribute(:requisition_id, nil)
    end

    update :update do
      require_atomic? false
      accept [:name, :is_default]

      change Firmowid.Ash.Finances.Changes.ResetCurrencyDefaults,
        where: [changing(:is_default), attribute_equals(:is_default, true)]
    end

    read :list_for_sync do
      description "Cross-org read for background sync workers."
      multitenancy :bypass
      filter expr(not is_nil(gocardless_id))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :iban, :string, public?: true, allow_nil?: false
    attribute :gocardless_id, :string, public?: true
    attribute :institution_id, :string, public?: true
    attribute :institution_name, :string, public?: true
    attribute :owner_name, :string, public?: true
    attribute :currency, :string, public?: true
    attribute :name, :string, public?: true
    attribute :is_default, :boolean, public?: true, default: false

    # requisition_id kept as plain attribute — Requisition is an un-migrated
    # Ecto schema, not an Ash resource. Will become a relationship when
    # BankData migrates to Ash.
    attribute :requisition_id, :uuid, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    has_many :transactions, Firmowid.Ash.Finances.Transaction
  end

  identities do
    identity :unique_iban_per_org, [:iban, :organization_id]

    # Partial unique index: only one default account per currency per org.
    # The DB index is `bank_accounts_organization_id_currency_is_default_index`
    # (created in migration 20250117142507), mapped via `identity_index_names` above.
    identity :unique_default_per_currency, [:currency] do
      where expr(is_default == true)
    end
  end
end
