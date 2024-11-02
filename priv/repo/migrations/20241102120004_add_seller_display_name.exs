defmodule Firmowid.Repo.Migrations.AddSellerDisplayName do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :seller_display_name, :string
    end

    execute "UPDATE documents SET seller_display_name = seller"
  end
end
