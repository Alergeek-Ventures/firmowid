defmodule Firmowid.Repo.Migrations.CreateSellers do
  use Ecto.Migration

  def change do
    create table(:sellers, primary_key: false) do
      add :id, :uuid, primary_key: true
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
      add :account_number, :string
      add :organization_id, references(:organizations, on_delete: :nothing, type: :uuid)

      timestamps(type: :utc_datetime)
    end

    create index(:sellers, [:organization_id])
  end
end
