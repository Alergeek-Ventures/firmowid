defmodule Firmowid.Repo.Migrations.CreateImportedTransactions do
  use Ecto.Migration

  def change do
    create table(:imported_transactions) do
      add :transaction_id, :string
      add :internal_transaction_id, :string
      add :creditor_name, :string
      add :creditor_account, :string
      add :debtor_name, :string
      add :debtor_account, :string
      add :transaction_amount, :float
      add :transaction_currency, :string
      add :booking_date, :date
      add :value_date, :date
      add :remittance_information_unstructured, :string

      add :bank_account_id,
          references(
            :bank_accounts,
            on_delete: :nothing
          )

      timestamps(type: :utc_datetime)
    end
  end
end
