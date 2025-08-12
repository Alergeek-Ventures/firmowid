defmodule Firmowid.Repo.Migrations.AddArchivedAtInProject do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :archived_at, :date
    end

    create index(:projects, [:archived_at])
  end
end
