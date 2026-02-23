defmodule Firmowid.Repo.Migrations.CreateInvoiceShareTokens do
  use Ecto.Migration

  def change do
    alter table(:sales_invoices) do
      add :share_token, :string
    end

    create unique_index(:sales_invoices, [:share_token], where: "share_token IS NOT NULL")
  end
end
