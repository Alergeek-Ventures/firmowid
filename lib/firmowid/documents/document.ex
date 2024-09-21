defmodule Firmowid.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :seller, :string

    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date

    field :total_amount, :float
    field :currency, :string

    field :description, :string
    field :invoice_identifier, :string

    field :file_name, :string

    field :skip_invoicing, :boolean, default: false

    many_to_many :imported_transactions,
                 Firmowid.Finances.ImportedTransaction,
                 join_through: "documents_imported_transactions",
                 join_keys: [
                   document_id: :id,
                   imported_transaction_id: :id
                 ]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document, attrs \\ %{}) do
    document
    |> cast(attrs, [
      :seller,
      :sale_date,
      :issue_date,
      :due_date,
      :total_amount,
      :currency,
      :file_name,
      :description,
      :invoice_identifier,
      :skip_invoicing
    ])
    |> cast_assoc(:imported_transactions)
  end
end
