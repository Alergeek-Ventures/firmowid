defmodule Firmowid.CostInvoices.CostInvoice do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "cost_invoices" do
    belongs_to :blob, Firmowid.Blobs.Blob
    belongs_to :inbound_email, Firmowid.CostInvoices.InboundEmail

    field :seller, :string
    field :seller_address, :string
    field :seller_display_name, :string
    field :account_number, :string

    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date

    field :total_amount, :decimal
    field :currency, :string

    field :description, :string
    field :invoice_identifier, :string

    field :skip_invoicing, :boolean, default: false

    field :blob_url, :string, virtual: true

    many_to_many :transactions,
                 Firmowid.Finances.Transaction,
                 join_through: "cost_invoices_transactions"

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(document, attrs \\ %{}) do
    document
    |> cast(attrs, [
      :blob_id,
      :inbound_email_id,
      :seller,
      :seller_address,
      :seller_display_name,
      :account_number,
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
    |> foreign_key_constraint(:inbound_email_id)
  end
end
