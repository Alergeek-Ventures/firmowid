defmodule Firmowid.Ash.Finances.BankAccount do
  @moduledoc """
  Ash resource wrapping the existing `bank_accounts` table.

  Attribute multitenancy via `organization_id`. Supports:

  - Standard CRUD (create, read, update, destroy)
  - `sync_from_bank` — upsert on `[:iban, :organization_id]` for GoCardless sync
  - `create_manual` — create a manual (non-GoCardless) bank account
  - `rename` — update only the name
  - `make_default` — transactionally reset same-currency defaults, then set one
  - `list_for_sync` — cross-org read for background sync worker (no authorization)
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "bank_accounts"
    repo(Firmowid.Repo)
    migrate?(false)
  end

  code_interface do
    define :read
    define :get_by_id, action: :by_id, args: [:id]
    define :sync_from_bank
    define :create_manual
    define :update
    define :rename, args: [:name]
    define :make_default
    define :destroy
    define :list_for_sync
  end

  actions do
    defaults [:read, :destroy]

    read :by_id do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    create :sync_from_bank do
      description "Upsert a bank account from GoCardless sync. On conflict by IBAN+org, updates bank metadata but preserves user-set name and is_default."

      # :name is accepted so it's set on initial insert (from GoCardless API),
      # but NOT listed in upsert_fields — on conflict, name is preserved
      # (user may have renamed the account).
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
      description "Create a manual (non-GoCardless) bank account. Sets institution_name to 'Manual' and nils GoCardless-specific fields."

      accept [:iban, :name, :currency, :is_default, :owner_name]

      change set_attribute(:institution_name, "Manual")
      change set_attribute(:gocardless_id, nil)
      change set_attribute(:institution_id, nil)
      change set_attribute(:requisition_id, nil)

      upsert? true
      upsert_identity :unique_iban_per_org

      upsert_fields [
        :institution_name,
        :owner_name,
        :currency,
        :gocardless_id,
        :institution_id,
        :requisition_id
      ]
    end

    update :update do
      accept [:name, :is_default]
    end

    update :rename do
      description "Rename a bank account."

      argument :name, :string, allow_nil?: false
      change set_attribute(:name, arg(:name))
    end

    action :make_default, :struct do
      description """
      Transactionally reset all same-currency bank accounts' is_default to false,
      then set this account as default. Returns the updated bank account.
      """

      constraints instance_of: __MODULE__

      argument :id, :uuid, allow_nil?: false

      run fn input, context ->
        bank_account =
          __MODULE__
          |> Ash.Query.for_read(:read, %{}, actor: context.actor, tenant: context.tenant)
          |> Ash.Query.do_filter(id: input.arguments.id)
          |> Ash.read_one!(actor: context.actor, tenant: context.tenant)

        bank_account
        |> Ash.Changeset.for_update(:set_as_default, %{},
          actor: context.actor,
          tenant: context.tenant
        )
        |> Ash.update(actor: context.actor, tenant: context.tenant, authorize?: false)
      end
    end

    update :set_as_default do
      description "Sets this bank account as default. Resets same-currency siblings via change module."
      require_atomic? false
      accept []
      change set_attribute(:is_default, true)
      change Firmowid.Ash.Finances.Changes.ResetCurrencyDefaults
    end

    read :list_for_sync do
      description "Lists bank accounts with a GoCardless ID for background sync. Bypasses multitenancy — called from Oban workers that dispatch across all orgs. Uses authorize?: false at the call site (system actor pattern placeholder)."

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

    # list_for_sync bypasses multitenancy and authorization (background worker).
    # Called with authorize?: false — placeholder for future system actor.
    policy action(:list_for_sync) do
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
