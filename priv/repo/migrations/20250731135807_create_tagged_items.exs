defmodule Firmowid.Repo.Migrations.CreateTaggedItems do
  use Ecto.Migration

  def change do
    create table(:tagged_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tag_id, references(:tags, type: :binary_id), null: false
      add :entity_type, :string, null: false
      add :entity_id, :binary_id, null: false
      add :organization_id, references(:organizations, type: :binary_id), null: false

      timestamps()
    end

    create unique_index(:tagged_items, [:entity_type, :entity_id, :tag_id])
    create index(:tagged_items, [:tag_id])
    create index(:tagged_items, [:entity_type, :entity_id])
  end
end
