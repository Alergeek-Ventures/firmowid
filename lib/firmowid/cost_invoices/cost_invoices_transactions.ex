defmodule Firmowid.CostInvoices.CostInvoicesTransactions do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "cost_invoices_transactions" do
    belongs_to :cost_invoice, Firmowid.CostInvoices.CostInvoice
    belongs_to :transaction, Firmowid.Ash.Finances.Transaction

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :cost_invoice_id,
      :transaction_id,
      :organization_id
    ])
    |> foreign_key_constraint(:transaction_id,
      name: "cost_invoices_transactions_transaction_id_fkey"
    )
    |> foreign_key_constraint(:cost_invoice_id,
      name: "cost_invoices_transactions_cost_invoice_id_fkey"
    )
  end
end
