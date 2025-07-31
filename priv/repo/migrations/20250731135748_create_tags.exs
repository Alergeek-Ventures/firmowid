defmodule Firmowid.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :color, :string, default: "#6B7280"
      add :organization_id, references(:organizations, type: :binary_id), null: false

      timestamps()
    end

    create unique_index(:tags, [:organization_id, :name])
  end
end
