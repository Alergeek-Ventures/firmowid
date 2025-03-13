defmodule Firmowid.Repo.Migrations.DropSellersTable do
  use Ecto.Migration

  def change do
    drop constraint(:sales_invoices, :sales_invoices_seller_id_fkey)

    alter table(:sales_invoices) do
      remove :seller_id
    end

    drop table(:sellers)
  end
end
