defmodule Firmowid.Repo.Migrations.AddMailAddress do
  use Ecto.Migration

  def change do
    alter table(:buyers) do
      add :is_different_mail_address, :boolean
      add :mail_street, :string
      add :mail_postal_code, :string
      add :mail_city, :string
      add :mail_country, :string
    end

    alter table(:invoices) do
      add :buyer_is_different_mail_address, :boolean
      add :buyer_mail_street, :string
      add :buyer_mail_postal_code, :string
      add :buyer_mail_city, :string
      add :buyer_mail_country, :string
    end
  end
end
