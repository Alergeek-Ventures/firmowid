defmodule Firmowid.Ash.Finances.Transaction do
  @moduledoc """
  Bank transaction synced from GoCardless.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJido],
    notifiers: [Ash.Notifier.PubSub],
    primary_read_warning?: false

  alias AshMoney.Types.Money
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Finances.Transaction.Calculations
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Preparations.ParadeDBSearch
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "transactions"
    repo Firmowid.Repo
  end

  jido do
    action :read,
      name: "list_transactions",
      description: "Listuje transakcje z bezpiecznymi filtrami Ash.",
      category: "ash.finances.read",
      tags: ["assistant", "transactions"]
  end

  actions do
    read :read do
      primary? true

      description """
      Lists transactions with optional filtering.

      All arguments are optional:
      - `date_from`, `date_to` — date range on `booking_date`.
      - `currency` — exact ISO currency code filter on `amount`.
      - `reconciliation`:
        - `:matched` (linked to an invoice)
        - `:pending` (unmatched, not skipped)
        - `:skipped` (unmatched, skipped)
        - `nil` - omit for all transactions
      - `query` — ParadeDB full-text search across debtor_name, creditor_name,
        and remittance_information_unstructured. When provided,
        results are sorted by relevance score.

      Sorting and relationship loading are controlled at the callsite.
      """

      argument :date_from, :date
      argument :date_to, :date
      argument :query, :string
      argument :currency, :string

      argument :reconciliation, :atom do
        constraints one_of: [:matched, :skipped, :pending]
      end

      prepare build(filter: expr(booking_date >= ^arg(:date_from))) do
        where present(:date_from)
      end

      prepare build(filter: expr(booking_date <= ^arg(:date_to))) do
        where present(:date_to)
      end

      prepare build(filter: expr(amount[:currency] == ^arg(:currency))) do
        where present(:currency)
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

      prepare {ParadeDBSearch, columns: ~w(debtor_name creditor_name remittance_information_unstructured)}
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
        :amount,
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
        :amount,
        :booking_date,
        :value_date,
        :remittance_information_unstructured,
        :bank_account_id
      ]
    end

    update :set_skip_invoicing do
      description "Set whether this transaction should be skipped during matching and invoicing."
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
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:analysis_reader, :ksef_digest]} do
      authorize_if action_type(:read)
    end

    # :invoicing and :accountant: read-only
    policy [action_type(:read), {AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # :accountant+: set_skip_invoicing (only user-facing update)
    policy [action_type(:update), {AtLeastRole, role: :accountant}] do
      authorize_if always()
    end

    # Write actions (non-system, non-admin): admin only
    policy action_type([:create, :destroy]) do
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
    attribute :amount, Money, public?: true, allow_nil?: false
    attribute :booking_date, :date, public?: true, allow_nil?: false
    attribute :value_date, :date, public?: true, allow_nil?: false
    attribute :remittance_information_unstructured, :string, public?: true

    # Firmowid data
    attribute :skip_invoicing, :boolean, public?: true, default: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :bank_account, Firmowid.Ash.Finances.BankAccount do
      allow_nil? false
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
    calculate :date, :date, expr(booking_date)

    calculate :direction, :atom, Calculations.Direction do
      public? true
      constraints one_of: [:income, :expense]

      description "Canonical transaction direction, preferring connected account ownership over amount sign."
    end

    calculate :signed_amount, Money, Calculations.SignedAmount do
      public? true
      description "Transaction amount signed according to its canonical direction."
    end

    calculate :counterparty_name, :string, Calculations.CounterpartyName do
      public? true
      description "Raw counterparty name selected according to transaction direction."
    end

    calculate :counterparty_display_name, :string, Calculations.CounterpartyDisplayName do
      public? true
      description "Useful counterparty name, with a Polish fallback when unavailable."
    end

    calculate :groupable?, :boolean, Calculations.Groupable do
      public? true
      description "Whether the transaction can be grouped for invoicing."
    end
  end

  aggregates do
    exists :has_cost_invoices?, :cost_invoices do
      public? false
      description "Whether the transaction has linked cost invoices."
    end

    exists :has_sales_invoices?, :sales_invoices do
      public? false
      description "Whether the transaction has linked sales invoices."
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
