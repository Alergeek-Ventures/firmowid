defmodule Firmowid.Documents.CostInvoicesTransactions do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "cost_invoices_transactions" do
    belongs_to :cost_invoice, Firmowid.Documents.CostInvoice
    belongs_to :transaction, Firmowid.Finances.Transaction

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :cost_invoice_id,
      :transaction_id,
      :organization_id
    ])
  end
end
