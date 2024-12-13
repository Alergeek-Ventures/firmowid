defmodule Firmowid.Repo.Migrations.CreateBuyers do
  use Ecto.Migration

  def change do
    create table(:buyers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :buyer_type, :string
      add :nip, :string
      add :display_name, :string
      add :name, :string
      add :surname, :string
      add :street, :string
      add :house_number, :string
      add :apartment_number, :string
      add :postal_code, :string
      add :city, :string
      add :country, :string
      add :email, :string
      add :phone, :string
      add :description, :string
      add :organization_id, references(:organizations, on_delete: :nothing, type: :uuid)

      timestamps(type: :utc_datetime)
    end

    create index(:buyers, [:organization_id])
  end
end
