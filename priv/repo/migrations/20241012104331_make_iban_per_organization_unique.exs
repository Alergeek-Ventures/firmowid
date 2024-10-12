defmodule Firmowid.Repo.Migrations.MakeIbanPerOrganizationUnique do
  use Ecto.Migration

  def change do
    create unique_index(:bank_accounts, [:iban, :organization_id])
    create unique_index(:imported_transactions, [:internal_transaction_id, :organization_id])
    drop unique_index(:imported_transactions, [:transaction_id, :organization_id])

    alter table(:bank_accounts) do
      add :requisition_id,
          references(:requisitions,
            on_delete: :delete_all,
            type: :bigint
          ),
          null: false
    end
  end
end
