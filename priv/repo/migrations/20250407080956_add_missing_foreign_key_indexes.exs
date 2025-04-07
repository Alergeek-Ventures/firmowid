defmodule Firmowid.Repo.Migrations.AddMissingIndexesAndDropUnusedOnes do
  use Ecto.Migration

  def change do
    # Add missing indexes
    create index(:projects_users, [:organization_id])
    create index(:projects_users, [:user_id])
    create index(:projects_users, [:project_id])
    create index(:projects, [:organization_id])
    create index(:sales_invoices_transactions, [:organization_id])
    create index(:sales_invoices_transactions, [:transaction_id])
    create index(:organization_invites, [:organization_id])
    create index(:cost_invoices_transactions, [:organization_id])
    create index(:cost_invoices_transactions, [:transaction_id])
    create index(:requisitions, [:organization_id])
    create index(:bank_accounts, [:requisition_id])
    create index(:users, [:organization_id])
    create index(:buyers, [:organization_id])
    create index(:sales_invoice_items, [:organization_id])
    create index(:sales_invoices, [:organization_id])
    create index(:sales_invoices, [:buyer_id])
    create index(:cost_invoices, [:organization_id])
    create index(:sessions, [:organization_id])
    create index(:sessions, [:project_id])
    create index(:sessions, [:user_id])
    create index(:blobs, [:organization_id])
    create index(:transactions, [:transaction_id])
    create index(:transactions, [:organization_id])
  end
end
