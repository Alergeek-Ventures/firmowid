defmodule Firmowid.Repo.Migrations.CreateHoursRecords do
  use Ecto.Migration

  def change do
    create table(:hours_records) do
      add :month, :integer, null: false
      add :year, :integer, null: false
      add :number_of_hours, :integer, null: false
      add :blob_id, references(:blobs, on_delete: :nilify_all)
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: false

      timestamps()
    end

    create index(:hours_records, [:blob_id])
    create index(:hours_records, [:organization_id])
    create index(:hours_records, [:user_id])

    create unique_index(:hours_records, [:month, :year, :organization_id, :user_id])
  end
end
