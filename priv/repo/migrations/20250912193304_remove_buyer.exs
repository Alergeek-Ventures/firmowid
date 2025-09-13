defmodule Firmowid.Repo.Migrations.RemoveBuyer do
  use Ecto.Migration

  def change do
    alter table(:sales_invoices) do
      remove :buyer_id
    end

    drop table(:buyers)
  end
end
