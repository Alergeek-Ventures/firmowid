defmodule Firmowid.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:organizations) do
      add :identification_number, :string, null: false
      add :address, :string
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps()
    end

    create table(:users) do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime
      add :system_role, :string, default: "user"

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          )

      timestamps()
    end

    alter table(:organizations) do
      add :owner_id, references(:users, on_delete: :delete_all), null: false
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
