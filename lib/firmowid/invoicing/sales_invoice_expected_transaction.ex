defmodule Firmowid.Invoicing.SalesInvoiceExpectedTransaction do
  @moduledoc """
  Join resource linking sales invoices to the expected transactions that pay them.

  An invoice paid on issue documents a payment already received; its expected transaction stands
  in for that payment until the bank transaction arrives and fulfils it.
  """
  use Ash.Resource,
    domain: Firmowid.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Resource

  require Resource

  postgres do
    table "sales_invoices_expected_transactions"
    repo Firmowid.Repo

    references do
      reference :sales_invoice, on_delete: :delete
      # The default name is longer than PostgreSQL's 63-character limit.
      reference :expected_transaction,
        on_delete: :delete,
        name: "sales_invoices_expected_transactions_expected_fkey"
    end
  end

  code_interface do
    define :read, action: :read
    define :create, action: :create
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy, create: [:sales_invoice_id, :expected_transaction_id]]
  end

  policies do
    bypass {SystemActorRole, roles: [:sales_invoice_processor]} do
      authorize_if always()
    end

    bypass [{SystemActorRole, roles: [:invoice_matcher, :analysis_reader]}, action_type(:read)] do
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
    belongs_to :sales_invoice, Firmowid.Invoicing.SalesInvoice do
      allow_nil? false
      public? true
    end

    belongs_to :expected_transaction, Firmowid.Finances.ExpectedTransaction do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_link, [:sales_invoice_id, :expected_transaction_id]
  end
end
