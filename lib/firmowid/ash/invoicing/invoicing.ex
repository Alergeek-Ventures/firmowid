defmodule Firmowid.Ash.Invoicing do
  @moduledoc """
  Ash domain for invoicing — counterparties, sales invoices, cost invoices,
  and supporting resources.

  Migrated incrementally from the legacy `SalesInvoices`, `CostInvoices`,
  and `Invoicing` Ecto contexts.
  """
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Invoicing.Counterparty
    resource Firmowid.Ash.Invoicing.InboundEmail
    resource Firmowid.Ash.Invoicing.SalesInvoiceTransaction
    resource Firmowid.Ash.Invoicing.CostInvoiceTransaction
    resource Firmowid.Ash.Invoicing.CostInvoice
    resource Firmowid.Ash.Invoicing.SalesInvoice
    resource Firmowid.Ash.Invoicing.SalesInvoiceItem
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
