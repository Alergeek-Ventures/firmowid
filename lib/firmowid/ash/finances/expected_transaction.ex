defmodule Firmowid.Ash.Finances.ExpectedTransaction do
  @moduledoc "An expected cash movement, fulfilled only by an explicitly linked bank transaction."
  use Ash.Resource,
    domain: Firmowid.Ash.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshMoney.Types.Money
  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "expected_transactions"
    repo Firmowid.Repo
  end

  actions do
    defaults [:read]

    create :create do
      description "Record an expected cash movement without creating a bank transaction."
      accept [:date, :amount, :description, :counterparty_name]
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

      prepare build(filter: expr(is_nil(transaction_id))) do
        where argument_equals(:fulfilled, false)
      end

      prepare build(filter: expr(not is_nil(transaction_id))) do
        where argument_equals(:fulfilled, true)
      end
    end

    update :connect_transaction do
      description "Fulfil an expectation with one tenant-owned transaction; an existing link cannot be replaced."
      accept []
      argument :transaction_id, :uuid, allow_nil?: false
      require_atomic? false

      # The write filter also protects against a competing update using a stale draft.
      change filter(expr(is_nil(transaction_id) or transaction_id == ^arg(:transaction_id)))
      change manage_relationship(:transaction_id, :transaction, type: :append_and_remove)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {AtLeastRole, role: :invoicing}
    end

    policy action_type([:create, :update]) do
      authorize_if {AtLeastRole, role: :accountant}
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "expected_transaction"

    publish :create, ["updated", :_tenant]
    publish :connect_transaction, ["updated", :_tenant]
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
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :transaction, Firmowid.Ash.Finances.Transaction do
      allow_nil? true
    end
  end

  identities do
    identity :unique_transaction, [:transaction_id]
  end
end
