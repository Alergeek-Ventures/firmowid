defmodule Firmowid.Repo.Migrations.AddKsefSupport do
  use Ecto.Migration

  def change do
    # KSeF credentials table
    create table(:ksef_credentials) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :auth_type, :string, null: false
      add :credentials, :binary, null: false

      timestamps()
    end

    create unique_index(:ksef_credentials, [:organization_id])

    # Cost invoices modifications for KSeF support
    alter table(:cost_invoices) do
      # Make fields nullable for KSeF-sourced invoices
      modify :blob_id, :binary_id, null: true

      # KSeF tracking
      add :ksef_number, :string, null: true
      add :ksef_permanent_storage_date, :utc_datetime_usec
      add :ksef_downloaded_at, :utc_datetime_usec

      # Enhanced seller information from KSeF
      add :seller_nip, :string, size: 10
      add :seller_country_code, :string, size: 2
      add :seller_email, :string
      add :seller_phone, :string

      # Invoice type information
      add :invoice_type, :string
      add :original_invoice_number, :string

      # Payment information
      add :payment_method, :string
    end

    create unique_index(:cost_invoices, [:ksef_number], name: :cost_invoices_ksef_number_idx)
  end
end
