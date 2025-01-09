defmodule Firmowid.Documents.DocumentsTransactions do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "documents_imported_transactions" do
    field :document_id, :integer
    field :imported_transaction_id, :integer

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document_imported_transaction, attrs \\ %{}) do
    document_imported_transaction
    |> cast(attrs, [
      :document_id,
      :imported_transaction_id,
      :organization_id
    ])
  end
end
