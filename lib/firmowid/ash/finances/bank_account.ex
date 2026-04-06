defmodule Firmowid.Ash.Finances.BankAccount do
  @moduledoc """
  Bank accounts synced from GoCardless or created manually.

  Uses AshEvents to track sync history. Sync status is derived via unrelated
  aggregates on the Event resource:
  - `has_successful_sync?` — exists aggregate, true if any sync succeeded
  - `broken?` — expression calculation over `latest_sync_action` first aggregate

  Uses AshOban for periodic transaction sync from GoCardless.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshEvents.Events, AshOban]

  alias Elixir.Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Events.Event
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

  events do
    # Track action events for derivation of sync status.
    # Used only for derivation, not replay.
    event_log Event
    only_actions [:sync_from_gocardless, :mark_sync_failed]
  end

  oban do
    triggers do
      trigger :sync_transactions do
        action :sync_from_gocardless
        where expr(not is_nil(gocardless_id))
        scheduler_cron "0 12 */2 * *"
        max_attempts 5
        on_error :mark_sync_failed
        queue :bank_data

        worker_module_name Firmowid.Ash.Finances.BankAccount.Worker.SyncTransactions
        scheduler_module_name Firmowid.Ash.Finances.BankAccount.Scheduler.SyncTransactions
      end
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true

      # Required for AshOban trigger support
      pagination do
        required? false
        offset? true
        keyset? true
      end
    end

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

    update :sync_from_gocardless do
      require_atomic? false

      description """
      Syncs transactions from GoCardless for this bank account.
      Triggered by AshOban scheduler every 2 days.
      """

      change Firmowid.Ash.Finances.Changes.SyncTransactions
    end

    update :mark_sync_failed do
      require_atomic? false

      description """
      on_error handler for sync_from_gocardless.
      Called when sync exhausts all retry attempts.
      """

      # No changes needed — the action event is logged automatically by AshEvents,
      # and the Broken calculation derives status from the event log.
    end
  end

  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # invoice_matcher and cost_invoice_processor: read-only access
    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:invoice_matcher, :cost_invoice_processor]} do
      authorize_if action_type(:read)
    end

    # :invoicing and :accountant: read-only
    policy [action_type(:read), {Firmowid.Ash.Checks.AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # Write actions: admin only (non-AshOban)
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
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

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :requisition, Firmowid.Ash.Finances.Requisition do
      attribute_writable? true

      description "The requisition that created this bank account (GoCardless-linked accounts only)."
    end

    has_many :transactions, Firmowid.Ash.Finances.Transaction
  end

  calculations do
    calculate :broken?, :boolean, expr(latest_sync_action == :mark_sync_failed) do
      public? true
      description "True if the most recent sync failed permanently."
    end
  end

  aggregates do
    exists :has_successful_sync?, Event do
      filter expr(
               record_id == parent(id) and
                 resource == BankAccount and
                 action == :sync_from_gocardless
             )

      public? true
      description "True if at least one sync has succeeded."
    end

    first :latest_sync_action, Event, :action do
      filter expr(
               record_id == parent(id) and
                 resource == BankAccount and
                 action in [:sync_from_gocardless, :mark_sync_failed]
             )

      sort occurred_at: :desc
      description "The action name of the most recent sync-related event."
    end
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
