defmodule Firmowid.Repo.Migrations.AddSellerAndBuyerToInvoice do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add :buyer_id, references(:buyers, on_delete: :nilify_all, type: :uuid)
      add :seller_id, references(:sellers, on_delete: :nilify_all, type: :uuid)
    end
  end
end
