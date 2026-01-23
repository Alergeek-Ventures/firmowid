defmodule Firmowid.Repo.Migrations.CreateContractors do
  use Ecto.Migration

  def change do
    create table(:contractors) do
      add :type, :string, null: false
      add :tax_id, :string
      add :display_name, :string
      add :name, :string
      add :surname, :string
      add :pesel, :string

      add :address, :string
      add :country, :string

      add :is_different_mail_address, :boolean, null: false, default: false
      add :mail_address, :string
      add :mail_country, :string

      add :email, :string
      add :phone, :string
      add :description, :string

      add :organization_id,
          references(:organizations, on_delete: :delete_all),
          null: false

      timestamps()
    end

    create index(:contractors, [:organization_id])
    create index(:contractors, [:type])
    create index(:contractors, [:tax_id])

    alter table(:sales_invoices) do
      add :contractor_id, references(:contractors, on_delete: :nilify_all)
    end

    create index(:sales_invoices, [:contractor_id])
  end
end
