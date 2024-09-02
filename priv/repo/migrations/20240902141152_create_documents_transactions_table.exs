defmodule Firmowid.Repo.Migrations.AddDocumentsTransactionsTable do
  use Ecto.Migration

  def change do
    create table(:documents_imported_transactions) do
      add :imported_transaction_id,
          references(:imported_transactions, type: :string)

      add :document_id,
          references(:documents)

      timestamps(type: :utc_datetime)
    end
  end
end
