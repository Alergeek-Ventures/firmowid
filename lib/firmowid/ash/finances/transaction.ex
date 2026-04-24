defmodule Firmowid.Ash.Finances.Transaction do
  @moduledoc """
  Bank transaction synced from GoCardless.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    primary_read_warning?: false

  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Finances.Calculations.TransactionAmount
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Preparations.ParadeDBSearch
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "transactions"
    repo Firmowid.Repo
  end

  actions do
    read :read do
      primary? true

      description """
      Lists transactions with optional filtering.

      All arguments are optional:
      - `date_from`, `date_to` — date range on `booking_date`.
      - `reconciliation`:
        - `:matched` (linked to an invoice)
        - `:pending` (unmatched, not skipped)
        - `:skipped` (unmatched, skipped)
        - `nil` - omit for all transactions
      - `query` — ParadeDB full-text search across debtor_name, creditor_name,
        remittance_information_unstructured, and transaction_currency. When provided,
        results are sorted by relevance score.

      Sorting and relationship loading are controlled at the callsite.
      """

      argument :date_from, :date
      argument :date_to, :date
      argument :query, :string

      argument :reconciliation, :atom do
        constraints one_of: [:matched, :skipped, :pending]
      end

      prepare build(filter: expr(booking_date >= ^arg(:date_from))) do
        where present(:date_from)
      end

      prepare build(filter: expr(booking_date <= ^arg(:date_to))) do
        where present(:date_to)
      end

      # :pending — unmatched and not skipped
      prepare build(
                filter:
                  expr(
                    not exists(cost_invoices, true) and
                      not exists(sales_invoices, true) and
                      skip_invoicing == false
                  )
              ) do
        where argument_equals(:reconciliation, :pending)
      end

      # :matched — linked to at least one invoice
      prepare build(
                filter:
                  expr(
                    exists(cost_invoices, true) or
                      exists(sales_invoices, true)
                  )
              ) do
        where argument_equals(:reconciliation, :matched)
      end

      # :skipped — unmatched and skipped
      prepare build(
                filter:
                  expr(
                    not exists(cost_invoices, true) and
                      not exists(sales_invoices, true) and
                      skip_invoicing == true
                  )
              ) do
        where argument_equals(:reconciliation, :skipped)
      end

      prepare {ParadeDBSearch,
               columns: ~w(debtor_name creditor_name remittance_information_unstructured transaction_currency)}
    end

    create :upsert_from_sync do
      description "Upsert a transaction from bank API sync."

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
        :bank_account_id,
        :skip_invoicing
      ]

      upsert? true
      upsert_identity :unique_internal_tx_per_account

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

    update :set_skip_invoicing do
      accept [:skip_invoicing]
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # invoice_matcher: full access for transaction linking
    bypass {SystemActorRole, roles: [:invoice_matcher]} do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:bank_sync]} do
      authorize_if action(:upsert_from_sync)
    end

    bypass {SystemActorRole, roles: [:analysis_reader]} do
      authorize_if action_type(:read)
    end

    # Other system actors: read-only access
    bypass Firmowid.Ash.Checks.IsSystemActor do
      authorize_if action_type(:read)
    end

    # :invoicing and :accountant: read-only
    policy [action_type(:read), {Firmowid.Ash.Checks.AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # Write actions (non-system, non-admin): admin only
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "transaction"

    publish :upsert_from_sync, ["updated", :_tenant]
    publish :set_skip_invoicing, ["updated", :_tenant]
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
    attribute :booking_date, :date, public?: true, allow_nil?: false
    attribute :value_date, :date, public?: true, allow_nil?: false
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

    many_to_many :cost_invoices, Firmowid.Ash.Invoicing.CostInvoice do
      through CostInvoiceTransaction
      source_attribute_on_join_resource :transaction_id
      destination_attribute_on_join_resource :cost_invoice_id
    end

    many_to_many :sales_invoices, Firmowid.Ash.Invoicing.SalesInvoice do
      through SalesInvoiceTransaction
      source_attribute_on_join_resource :transaction_id
      destination_attribute_on_join_resource :sales_invoice_id
    end
  end

  calculations do
    calculate :amount, :struct, TransactionAmount do
      constraints instance_of: Money
      public? true

      description "Transaction amount as a Money struct."
    end
  end

  identities do
    identity :unique_internal_tx_per_account, [
      :internal_transaction_id,
      :bank_account_id,
      :organization_id
    ]
  end
end
