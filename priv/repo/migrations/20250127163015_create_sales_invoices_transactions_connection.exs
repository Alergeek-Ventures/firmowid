defmodule Firmowid.Repo.Migrations.CreateSalesInvoicesTransactionsConnection do
  use Ecto.Migration

  def change do
    create table(:sales_invoices_transactions) do
      add :sales_invoice_id, references(:sales_invoices, on_delete: :delete_all), null: false
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps()
    end
  end
end
