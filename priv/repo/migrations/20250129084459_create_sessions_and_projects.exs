defmodule Firmowid.Repo.Migrations.CreateSessionsAndProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all,
            type: :uuid
          ),
          null: false

      timestamps()
    end

    create table(:projects_users) do
      add :project_id,
          references(:projects,
            on_delete: :delete_all
          ),
          null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end

    create table(:sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime
      add :project_id, references(:projects, on_delete: :nilify_all)

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end
  end
end
