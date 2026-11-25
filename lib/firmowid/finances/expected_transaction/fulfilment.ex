defmodule Firmowid.Finances.ExpectedTransaction.Fulfilment do
  @moduledoc """
  Join resource linking expected transactions to the bank transactions that fulfil them.

  An implementation detail of `many_to_many :transactions` on `ExpectedTransaction`; links are
  made and removed only by its `connect_transactions` and `disconnect_transactions` actions.
  """
  use Ash.Resource,
    domain: Firmowid.Finances,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Resource

  require Resource

  postgres do
    table "expected_transaction_fulfilments"
    repo Firmowid.Repo

    references do
      reference :expected_transaction, on_delete: :delete
      reference :transaction, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
    define :create, action: :create
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy, create: [:expected_transaction_id, :transaction_id]]
  end

  policies do
    bypass [
      {SystemActorRole, roles: [:invoice_matcher, :analysis_reader, :sales_invoice_processor, :tax_forecaster]},
      action_type(:read)
    ] do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {AtLeastRole, role: :invoicing}
    end

    policy action_type([:create, :destroy]) do
      authorize_if {AtLeastRole, role: :accountant}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :organization_id, :uuid, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :expected_transaction, Firmowid.Finances.ExpectedTransaction do
      allow_nil? false
      public? true
    end

    belongs_to :transaction, Firmowid.Finances.Transaction do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_fulfilment, [:expected_transaction_id, :transaction_id]
  end
end
