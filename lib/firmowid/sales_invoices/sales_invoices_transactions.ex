defmodule Firmowid.SalesInvoices.SalesInvoicesTransactions do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "sales_invoices_transactions" do
    belongs_to :sales_invoice, Firmowid.SalesInvoices.SalesInvoice
    belongs_to :transaction, Firmowid.Finances.Transaction

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(attrs) do
    cast(%__MODULE__{}, attrs, [:sales_invoice_id, :transaction_id, :organization_id])
  end
end
