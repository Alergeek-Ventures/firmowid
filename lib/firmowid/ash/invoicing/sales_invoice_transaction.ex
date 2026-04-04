defmodule Firmowid.Ash.Invoicing.SalesInvoiceTransaction do
  @moduledoc """
  Join resource linking sales invoices to bank transactions.

  This is an implementation detail of the `many_to_many :transactions`
  relationship on `SalesInvoice`. All connection/disconnection logic
  lives in `SalesInvoice.connect_transactions` / `disconnect_transactions`
  actions, exposed via `Invoicing` domain code interface.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "sales_invoices_transactions"
    repo Firmowid.Repo
    migrate? false
  end

  actions do
    defaults [:read, :destroy, create: [:sales_invoice_id, :transaction_id]]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :sales_invoice_id, :uuid, allow_nil?: false, public?: true
    attribute :transaction_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false

    Resource.firmowid_timestamps()
  end
end
