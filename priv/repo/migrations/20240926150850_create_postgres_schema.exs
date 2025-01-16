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

    create table(:transactions) do
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

    create unique_index(:transactions, [:internal_transaction_id, :organization_id])

    create table(:blobs) do
      add :blob_path, :string, null: false
      add :original_filename, :string, null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end

    create table(:cost_invoices) do
      add :blob_id, references(:blobs, on_delete: :delete_all), null: false

      add :seller, :string, null: false
      add :seller_display_name, :string, null: false

      add :sale_date, :date, null: false
      add :issue_date, :date, null: false
      add :due_date, :date, null: false

      add :total_amount, :decimal, precision: 10, scale: 2, null: false
      add :currency, :string, null: false

      add :invoice_identifier, :string, null: false
      add :description, :text, null: false

      add :skip_invoicing, :boolean, default: false, null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all,
            type: :uuid
          ),
          null: false

      timestamps()
    end

    create unique_index(:cost_invoices, [:blob_id])
    create index(:cost_invoices, [:invoice_identifier])

    create table(:cost_invoices_transactions) do
      add :cost_invoice_id, references(:cost_invoices, on_delete: :delete_all), null: false

      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false

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
