defmodule Firmowid.Documents.CostInvoice do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "cost_invoices" do
    belongs_to :blob, Firmowid.Documents.Blob

    field :seller, :string
    field :seller_display_name, :string

    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date

    field :total_amount, :decimal
    field :currency, :string

    field :description, :string
    field :invoice_identifier, :string

    field :skip_invoicing, :boolean, default: false

    many_to_many :transactions,
                 Firmowid.Finances.Transaction,
                 join_through: "cost_invoices_transactions"

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document, attrs \\ %{}) do
    document
    |> cast(attrs, [
      :blob_id,
      :seller,
      :seller_display_name,
      :sale_date,
      :issue_date,
      :due_date,
      :total_amount,
      :currency,
      :description,
      :invoice_identifier,
      :skip_invoicing,
      :organization_id
    ])
    |> validate_required([
      :seller,
      :seller_display_name,
      :sale_date,
      :issue_date,
      :due_date,
      :total_amount,
      :currency,
      :description,
      :invoice_identifier,
      :skip_invoicing,
      :organization_id
    ])
  end
end
