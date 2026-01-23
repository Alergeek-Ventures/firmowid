defmodule Firmowid.Repo.Migrations.AddOrganizationLimits do
  use Ecto.Migration

  def change do
    create table(:organization_limits, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :cost_invoices_used, :integer, null: false, default: 0
      add :cost_invoices_limit, :integer, null: false, default: 100
      add :sales_invoices_used, :integer, null: false, default: 0
      add :sales_invoices_limit, :integer, null: false, default: 100
      add :bank_connections_used, :integer, null: false, default: 0
      add :bank_connections_limit, :integer, null: false, default: 5

      timestamps()
    end

    create unique_index(:organization_limits, [:organization_id])
  end
end
