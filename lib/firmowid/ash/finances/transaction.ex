defmodule Firmowid.Ash.Finances.Transaction do
  @moduledoc "Bank transaction synced from GoCardless, with internal notes and invoice matching."
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub],
    fragments: [
      Firmowid.Ash.Finances.Transaction.Policies,
      Firmowid.Ash.Finances.Transaction.Calculations
    ]

  alias AshMoney.Types.Money
  alias Firmowid.Ash.Finances.Transaction.Types
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Preparations.FilterByAmount
  alias Firmowid.Ash.Preparations.ParadeDBSearch
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "transactions"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :list, action: :list
    define :update_internal_note, args: [:internal_note], action: :update_internal_note
  end

  actions do
    defaults [:read]

    read :list do
      description """
      Lists bank transactions with optional filters.

      Sorting and relationship loading are controlled at the callsite. With a
      `query`, unpaginated results are sorted by ParadeDB relevance.
      """

      pagination do
        required? false
        keyset? true
        max_page_size 100
      end

      argument :date_from, :date, description: "Inclusive start of the booking date range (YYYY-MM-DD)."

      argument :date_to, :date, description: "Inclusive end of the booking date range (YYYY-MM-DD)."

      argument :query, :string,
        constraints: [max_length: 500],
        description: "Full-text search over the debtor, creditor and transfer title."

      argument :currency, :string, description: "ISO currency code, e.g. PLN."

      argument :amount_from, :decimal,
        description: "Minimum amount, inclusive, compared as an absolute value although expenses are negative."

      argument :amount_to, :decimal,
        description: "Maximum amount, inclusive, compared as an absolute value although expenses are negative."

      argument :ids, {:array, :uuid}, description: "Return only transactions with these IDs."

      argument :salary_user_id, :uuid, description: "Only transfers assigned to this employee's salary."

      argument :salary_month, :date, description: "Only transfers assigned to the salary of this month (first day)."

      argument :salary_assigned, :boolean, description: "Whether the transfer is assigned to a monthly salary."

      argument :reconciliation, :atom do
        constraints one_of: [:matched, :skipped, :pending]

        description "matched is linked to an invoice or a monthly salary, pending is unresolved, " <>
                      "skipped is excluded from matching."
      end

      prepare build(filter: expr(id in ^arg(:ids))) do
        where present(:ids)
      end

      prepare build(filter: expr(salary_user_id == ^arg(:salary_user_id))) do
        where present(:salary_user_id)
      end

      prepare build(filter: expr(salary_month == ^arg(:salary_month))) do
        where present(:salary_month)
      end

      prepare build(filter: expr(has_salary?)) do
        where argument_equals(:salary_assigned, true)
      end

      prepare build(filter: expr(not has_salary?)) do
        where argument_equals(:salary_assigned, false)
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

      prepare {FilterByAmount, []}

      prepare build(filter: expr(reconciliation_status == ^arg(:reconciliation))) do
        where present(:reconciliation)
      end

      prepare {ParadeDBSearch, columns: ~w(debtor_name creditor_name remittance_information_unstructured)a}
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

    update :update_internal_note do
      description "Replace the internal note without changing bank data or reconciliation."
      accept [:internal_note]
    end

    update :set_skip_invoicing do
      description "Set whether this transaction should be skipped during matching and invoicing."
      primary? true
      accept [:skip_invoicing]
      change filter(expr(invoice_matchable?))
    end

    update :restore_for_matching do
      description "Return a skipped transaction to pending matching; a pending one stays unchanged."
      accept []
      require_atomic? false
      validate Firmowid.Ash.Finances.Transaction.Validations.NotMatched
      change set_attribute(:skip_invoicing, false)
      change filter(expr(reconciliation_status != :matched))
    end

    update :connect_salary do
      description "Manually assign an outgoing transaction to one employee's salary month."
      accept [:salary_user_id, :salary_month]
      require_attributes [:salary_user_id, :salary_month]
      require_atomic? false

      change Firmowid.Ash.Finances.Changes.ConnectSalary
    end

    update :disconnect_salary do
      description "Remove a monthly salary assignment without changing the bank transaction."
      accept []
      change set_attribute(:salary_user_id, nil)
      change set_attribute(:salary_month, nil)
    end

    action :invoice_suggestions, {:array, Types.InvoiceSuggestion} do
      description "Score unresolved invoices against a pending transaction, best match first."

      argument :transaction_id, :uuid,
        allow_nil?: false,
        description: "ID of a pending transaction."

      run Firmowid.Ash.Finances.Transaction.Actions.InvoiceSuggestions
    end

    action :salary_suggestions, Types.SalarySuggestions do
      description "Find available salaries with submitted hours records; optional filters support manual assignment revalidation."

      argument :transaction_id, :uuid,
        allow_nil?: false,
        description: "ID of a pending or skipped outgoing PLN transfer."

      argument :salary_user_id, :uuid, description: "Only suggest this employee's salaries."

      argument :salary_month, :date, description: "Only suggest the salary of this month (first day)."

      argument :submitted_hours_only?, :boolean do
        allow_nil? false
        default true
        description "Only propose salaries with a submitted, non-withdrawn hours record."
      end

      run Firmowid.Ash.Finances.Transaction.Actions.SalarySuggestions
    end

    action :monthly_salaries, {:array, Types.MonthlySalary} do
      description "List every employee salary of one month with its hours record state and paying transfer."

      argument :month, :date,
        allow_nil?: false,
        description: "Any day of the salary month, e.g. 2026-01-01."

      argument :user_id, :uuid, description: "Only this employee's salary."

      argument :query, :string,
        constraints: [max_length: 200],
        description: "Case- and diacritic-insensitive part of the employee's name or email."

      run Firmowid.Ash.Finances.Transaction.Actions.MonthlySalaries
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "transaction"

    publish :upsert_from_sync, ["updated", :_tenant]
    publish :set_skip_invoicing, ["updated", :_tenant]
    publish :update_internal_note, ["updated", :_tenant]
    publish :restore_for_matching, ["updated", :_tenant]
    publish :connect_salary, ["updated", :_tenant]
    publish :disconnect_salary, ["updated", :_tenant]
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
    attribute :internal_note, :string, constraints: [max_length: 10_000]

    attribute :salary_month, :date, description: "First day of the salary month this transfer pays."

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :salary_user, Firmowid.Ash.Core.User do
      allow_nil? true
      attribute_writable? true
    end

    has_many :entity_tags, Firmowid.Ash.Analysis.EntityTag do
      relationship_context %{data_layer: %{table: "transaction_entity_tags"}}
      source_attribute :id
      destination_attribute :resource_id
      read_action :for_transactions
    end

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
    identity :unique_salary_month, [:salary_user_id, :salary_month, :organization_id]

    identity :unique_internal_tx_per_account, [
      :internal_transaction_id,
      :bank_account_id,
      :organization_id
    ]
  end
end
