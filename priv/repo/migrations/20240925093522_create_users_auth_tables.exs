defmodule Firmowid.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:organizations, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :identification_number, :string, null: false
      add :address, :string
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all,
            type: :uuid
          )

      timestamps(type: :utc_datetime)
    end

    alter table(:organizations) do
      add :owner_id, references(:users, on_delete: :delete_all, type: :uuid), null: false
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all, type: :uuid), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
