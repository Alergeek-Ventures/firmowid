defmodule Firmowid.Repo.Migrations.DropOrganizationLimits do
  use Ecto.Migration

  def up do
    drop_if_exists table(:organization_limits)
  end

  def down do
    create table(:organization_limits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id), null: false
      add :cost_invoices_used, :integer, default: 0
      add :cost_invoices_limit, :integer, default: 100
      add :sales_invoices_used, :integer, default: 0
      add :sales_invoices_limit, :integer, default: 100
      add :bank_connections_used, :integer, default: 0
      add :bank_connections_limit, :integer, default: 5

      timestamps()
    end

    create unique_index(:organization_limits, [:organization_id])
  end
end
