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
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end
