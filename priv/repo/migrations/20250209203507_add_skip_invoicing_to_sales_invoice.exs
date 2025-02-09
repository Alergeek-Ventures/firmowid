defmodule Firmowid.Repo.Migrations.AddSkipInvoicingToSalesInvoice do
  use Ecto.Migration

  def change do
    alter table(:sales_invoices) do
      add :skip_invoicing, :boolean, default: false, null: false
    end
  end
end
