defmodule Firmowid.Repo.Migrations.AddUniqueIndexInvoiceNumberOrganizatio do
  use Ecto.Migration

  def change do
    create unique_index(:sales_invoices, [:invoice_number, :organization_id])
  end
end
