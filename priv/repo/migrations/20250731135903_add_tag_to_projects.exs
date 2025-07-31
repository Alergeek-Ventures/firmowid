defmodule Firmowid.Repo.Migrations.AddTagToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :tag_id, references(:tags, type: :binary_id)
    end

    create index(:projects, [:tag_id])
  end
end
