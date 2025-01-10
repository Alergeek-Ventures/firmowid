defmodule Firmowid.Repo.Migrations.CreatePostgresSchema do
  use Ecto.Migration

  def change do
    create_requisition_status_query =
      "CREATE TYPE requisition_status AS ENUM ('pending', 'accepted', 'rejected')"

    execute(create_requisition_status_query)

    create table(:requisitions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status, :requisition_status, null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end

    create table(:bank_accounts) do
      add :iban, :string, null: false
      add :gocardless_id, :string, default: nil

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      add :requisition_id,
          references(:requisitions,
            on_delete: :nilify_all
          ),
          null: false

      timestamps()
    end

    create unique_index(:bank_accounts, [:iban, :organization_id])

    create table(:imported_transactions) do
      add :transaction_id, :string
      add :internal_transaction_id, :string
      add :creditor_name, :string
      add :creditor_account, :string
      add :debtor_name, :string
      add :debtor_account, :string
      add :transaction_amount, :decimal, precision: 10, scale: 2
      add :transaction_currency, :string
      add :booking_date, :date
      add :value_date, :date
      add :remittance_information_unstructured, :text

      add :skip_invoicing, :boolean, default: false

      add :bank_account_id, references(:bank_accounts, on_delete: :delete_all)

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end

    create unique_index(:imported_transactions, [:internal_transaction_id, :organization_id])

    create table(:documents) do
      add :seller, :string
      add :seller_display_name, :string

      add :sale_date, :date
      add :issue_date, :date
      add :due_date, :date

      add :total_amount, :decimal, precision: 10, scale: 2
      add :currency, :string

      add :invoice_identifier, :string
      add :description, :text

      add :file_name, :string

      add :skip_invoicing, :boolean, default: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all,
            type: :uuid
          ),
          null: false

      timestamps()
    end

    create index(:documents, [:invoice_identifier])

    create table(:documents_imported_transactions) do
      add :document_id, references(:documents, on_delete: :delete_all), null: false

      add :imported_transaction_id, references(:imported_transactions, on_delete: :delete_all),
        null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all,
            type: :uuid
          ),
          null: false

      timestamps()
    end
  end
end
