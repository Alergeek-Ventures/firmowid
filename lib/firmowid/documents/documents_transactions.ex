defmodule Firmowid.Documents.DocumentsTransactions do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents_imported_transactions" do
    field :document_id, :integer
    field :imported_transaction_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document, attrs \\ %{}) do
    document
    |> cast(attrs, [
      :document_id,
      :imported_transaction_id
    ])
  end
end
