defmodule Firmowid.Finances.ExpectedTransaction do
  @moduledoc """
  An expected cash movement, such as the payment an invoice paid on issue documents, fulfilled
  only by explicitly linked bank transactions.

  Expectations and bank transactions link many to many, like invoices and transactions: a
  payment gateway's payout fulfils the expectations of many orders, and an expectation may be
  paid in parts. A bank transaction that fulfils an expectation is matched, and an invoice whose
  payment is expected counts as paid.
  """
  use Ash.Resource,
    domain: Firmowid.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  use Gettext, backend: Firmowid.Gettext

  alias AshMoney.Types.Money
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Finances.ExpectedTransaction.Fulfilment
  alias Firmowid.Invoicing.SalesInvoiceExpectedTransaction
  alias Firmowid.Resource

  require Resource

  postgres do
    table "expected_transactions"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Record an expected cash movement, optionally the payment of sales invoices, " <>
                    "without creating a bank transaction."

      accept [:date, :amount, :description, :counterparty_name]
      argument :sales_invoice_ids, {:array, :uuid}, default: []

      change manage_relationship(:sales_invoice_ids, :sales_invoices, type: :append)
    end

    read :list do
      description "List expectations with optional date and fulfilment filters."
      argument :date_from, :date
      argument :date_to, :date
      argument :fulfilled, :boolean

      prepare build(filter: expr(date >= ^arg(:date_from))) do
        where present(:date_from)
      end

      prepare build(filter: expr(date <= ^arg(:date_to))) do
        where present(:date_to)
      end

      prepare build(filter: expr(is_fulfilled == ^arg(:fulfilled))) do
        where present(:fulfilled)
      end
    end

    update :connect_transactions do
      description "Fulfil the expectation with bank transactions that are not matched to anything else."
      primary? true
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      validate argument_does_not_equal(:transaction_ids, []),
        message: gettext_noop("Select at least one transaction.")

      change __MODULE__.Changes.ValidateTransactionAvailability
      change manage_relationship(:transaction_ids, :transactions, type: :append)
    end

    update :disconnect_transactions do
      description "Remove a wrong fulfilment; the transactions become pending again."
      require_atomic? false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false

      validate argument_does_not_equal(:transaction_ids, []),
        message: gettext_noop("Select at least one transaction.")

      change manage_relationship(:transaction_ids, :transactions, type: :remove)
    end
  end

  policies do
    # Issuing an invoice paid on issue records its payment, and returning it to a draft withdraws it.
    bypass {SystemActorRole, roles: [:sales_invoice_processor]} do
      authorize_if action_type([:read, :create, :destroy])
    end

    bypass [{SystemActorRole, roles: [:invoice_matcher, :analysis_reader]}, action_type(:read)] do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {AtLeastRole, role: :invoicing}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {AtLeastRole, role: :accountant}
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "expected_transaction"

    publish_all :create, ["updated", :_tenant]
    publish_all :update, ["updated", :_tenant]
    publish_all :destroy, ["updated", :_tenant]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true

    attribute :amount, Money do
      allow_nil? false
      public? true
      description "Signed amount: income is positive, expenses are negative."
    end

    attribute :description, :string, allow_nil?: false, public?: true
    attribute :counterparty_name, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    many_to_many :transactions, Firmowid.Finances.Transaction do
      public? true
      through Fulfilment
      source_attribute_on_join_resource :expected_transaction_id
      destination_attribute_on_join_resource :transaction_id
    end

    many_to_many :sales_invoices, Firmowid.Invoicing.SalesInvoice do
      public? true
      through SalesInvoiceExpectedTransaction
      source_attribute_on_join_resource :expected_transaction_id
      destination_attribute_on_join_resource :sales_invoice_id
    end
  end

  calculations do
    calculate :is_fulfilled, :boolean, expr(exists(transactions, true)) do
      public? true
      description "Whether a bank transaction fulfils the expectation."
    end
  end
end
