defmodule Firmowid.Ash.Finances.Transaction do
  @moduledoc """
  Ash resource wrapping the existing `transactions` table.

  Attribute multitenancy via `organization_id`. Supports:

  - `upsert_from_sync` — bulk-compatible create with upsert on
    `[:internal_transaction_id, :organization_id]` for bank API sync
  - `toggle_skip_invoicing` — flip the `skip_invoicing` boolean and broadcast
  - Complex read queries (search, unmatched, skipped) via generic actions
    backed by `TransactionQueries` helpers

  The `many_to_many` relationships to CostInvoice/SalesInvoice through their
  join tables are NOT declared here — those contexts haven't migrated to Ash
  yet. The generic actions that need join table data use raw Ecto queries.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Calculations.TransactionAmount
  alias Firmowid.Ash.Finances.TransactionQueries
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "transactions"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :read
    define :upsert_from_sync
    define :toggle_skip_invoicing, args: [:id]
    define :list_by_date_range, args: [:date_from, :date_to]
    define :list_unmatched, args: [:date_from, :date_to]
    define :list_skipped, args: [:date_from, :date_to]
    define :list_skipped_unmatched, args: [:date_from, :date_to]
    define :search
    define :get_by_ids, args: [:ids]
    define :bulk_upsert_from_sync, args: [:transactions]
  end

  actions do
    defaults [:read]

    create :upsert_from_sync do
      description "Upsert a transaction from bank API sync. On conflict by internal_transaction_id+org, updates all bank data but preserves skip_invoicing."

      accept [
        :transaction_id,
        :internal_transaction_id,
        :creditor_name,
        :creditor_account,
        :debtor_name,
        :debtor_account,
        :transaction_amount,
        :transaction_currency,
        :booking_date,
        :value_date,
        :remittance_information_unstructured,
        :bank_account_id
      ]

      upsert? true
      upsert_identity :unique_internal_tx_per_org

      upsert_fields [
        :transaction_id,
        :creditor_name,
        :creditor_account,
        :debtor_name,
        :debtor_account,
        :transaction_amount,
        :transaction_currency,
        :booking_date,
        :value_date,
        :remittance_information_unstructured,
        :bank_account_id
      ]
    end

    action :toggle_skip_invoicing, :struct do
      description "Flips the skip_invoicing boolean on a transaction and broadcasts the change."

      constraints instance_of: __MODULE__

      argument :id, :uuid, allow_nil?: false

      run fn input, context ->
        transaction =
          __MODULE__
          |> Ash.Query.for_read(:read, %{}, actor: context.actor, tenant: context.tenant)
          |> Ash.Query.do_filter(id: input.arguments.id)
          |> Ash.read_one!(actor: context.actor, tenant: context.tenant)

        # authorize?: false — the toggle generic action already passed policy
        # checks; the internal update is an implementation detail.
        updated =
          transaction
          |> Ash.Changeset.for_update(
            :set_skip_invoicing,
            %{skip_invoicing: !transaction.skip_invoicing},
            actor: context.actor,
            tenant: context.tenant
          )
          |> Ash.update!(actor: context.actor, tenant: context.tenant, authorize?: false)

        Finances.broadcast_transaction_list_updated(updated.organization_id)

        {:ok, updated}
      end
    end

    update :set_skip_invoicing do
      description "Sets the skip_invoicing boolean to the given value. Used internally by toggle_skip_invoicing."
      accept [:skip_invoicing]
    end

    action :bulk_upsert_from_sync, :integer do
      description """
      Bulk upsert transactions from bank API sync. Wraps `Ash.bulk_create/4`
      with upsert options. Returns the count of processed records.

      Broadcasts a single transaction_list_updated after the entire batch.
      """

      argument :transactions, {:array, :map}, allow_nil?: false

      run fn input, context ->
        transactions = input.arguments.transactions

        result =
          Ash.bulk_create(
            transactions,
            __MODULE__,
            :upsert_from_sync,
            actor: context.actor,
            authorize?: context.authorize?,
            tenant: context.tenant,
            upsert?: true,
            return_errors?: true,
            stop_on_error?: false,
            batch_size: 100
          )

        # Single broadcast after the entire bulk completes
        if context.tenant do
          Finances.broadcast_transaction_list_updated(context.tenant)
        end

        {:ok, length(transactions) - length(Map.get(result, :errors, []))}
      end
    end

    # ── Complex read queries (backed by TransactionQueries) ────────────

    action :list_by_date_range, {:array, :struct} do
      description "Lists transactions within a date range, ordered by booking_date desc."

      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      run fn input, context ->
        Firmowid.Repo.put_org_id(context.tenant)

        {:ok,
         TransactionQueries.list_by_date_range(
           input.arguments.date_from,
           input.arguments.date_to
         )}
      end
    end

    action :list_unmatched, {:array, :struct} do
      description "Lists transactions not matched to any invoice and not skipped, within a date range."

      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      run fn input, context ->
        Firmowid.Repo.put_org_id(context.tenant)

        {:ok,
         TransactionQueries.list_unmatched(
           input.arguments.date_from,
           input.arguments.date_to
         )}
      end
    end

    action :list_skipped, {:array, :struct} do
      description "Lists transactions with skip_invoicing=true within a date range."

      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      run fn input, context ->
        Firmowid.Repo.put_org_id(context.tenant)

        {:ok,
         TransactionQueries.list_skipped(
           input.arguments.date_from,
           input.arguments.date_to
         )}
      end
    end

    action :list_skipped_unmatched, {:array, :struct} do
      description "Lists transactions that are skipped AND not matched to any invoice. Used by Analysis to avoid double-counting."

      argument :date_from, :date, allow_nil?: false
      argument :date_to, :date, allow_nil?: false

      run fn input, context ->
        Firmowid.Repo.put_org_id(context.tenant)

        {:ok,
         TransactionQueries.list_skipped_unmatched(
           input.arguments.date_from,
           input.arguments.date_to
         )}
      end
    end

    action :search, {:array, :struct} do
      description "Full-text search using ParadeDB with optional filters. Uses raw Ecto for ParadeDB ~> operator and pdb.score() ordering."

      argument :query, :string
      argument :only_unmatched, :boolean, default: true
      argument :currency, :string
      argument :amount_gt, :decimal
      argument :amount_lt, :decimal
      argument :date_from, :date
      argument :date_to, :date

      run fn input, context ->
        Firmowid.Repo.put_org_id(context.tenant)
        {:ok, TransactionQueries.search(input.arguments)}
      end
    end

    action :get_by_ids, {:array, :struct} do
      description "Fetches transactions by a list of IDs."

      argument :ids, {:array, :uuid}, allow_nil?: false

      run fn input, context ->
        Firmowid.Repo.put_org_id(context.tenant)
        {:ok, TransactionQueries.get_by_ids(input.arguments.ids)}
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    # Read-like generic actions — open to all authenticated users
    policy action([
             :list_by_date_range,
             :list_unmatched,
             :list_skipped,
             :list_skipped_unmatched,
             :search,
             :get_by_ids
           ]) do
      authorize_if always()
    end

    # Mutating generic actions — admin-only (worker uses authorize?: false)
    policy action([:toggle_skip_invoicing, :bulk_upsert_from_sync]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

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

    # Data fetched from Bank API
    attribute :transaction_id, :string, public?: true
    attribute :internal_transaction_id, :string, public?: true
    attribute :creditor_name, :string, public?: true
    attribute :creditor_account, :string, public?: true
    attribute :debtor_name, :string, public?: true
    attribute :debtor_account, :string, public?: true
    attribute :transaction_amount, :decimal, public?: true
    attribute :transaction_currency, :string, public?: true
    attribute :booking_date, :date, public?: true
    attribute :value_date, :date, public?: true
    attribute :remittance_information_unstructured, :string, public?: true

    # Firmowid data
    attribute :skip_invoicing, :boolean, public?: true, default: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :bank_account, Firmowid.Ash.Finances.BankAccount do
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    # entity_tags via polymorphic table — not declared as a relationship.
    # EntityTag uses a single resource for all entity types with polymorphic tables.
    # Use EntityTag.for_transactions/0 action with filter resource_id == transaction_id
    # to load tags for a specific transaction.

    # many_to_many to CostInvoice/SalesInvoice — NOT declared.
    # Those contexts are un-migrated Ecto schemas. Generic actions
    # that need join table data use raw Ecto queries via TransactionQueries.
  end

  calculations do
    calculate :amount, :struct, TransactionAmount do
      constraints instance_of: Money
      public? true

      description "Transaction amount as a Money struct combining transaction_currency and transaction_amount."
    end
  end

  identities do
    identity :unique_internal_tx_per_org, [:internal_transaction_id, :organization_id]
  end
end
