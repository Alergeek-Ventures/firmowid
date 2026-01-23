defmodule Firmowid.Repo.Migrations.SalesInvoiceItemsItemIndex do
  use Ecto.Migration

  def change do
    alter table(:sales_invoice_items) do
      add :index, :integer
    end
  end
end
