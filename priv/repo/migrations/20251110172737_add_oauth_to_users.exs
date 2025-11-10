defmodule Firmowid.Repo.Migrations.AddOauthToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :provider, :string, default: "password", null: false
      add :provider_id, :string
    end

    # Allow null hashed_password for OAuth users
    execute "ALTER TABLE users ALTER COLUMN hashed_password DROP NOT NULL",
            "ALTER TABLE users ALTER COLUMN hashed_password SET NOT NULL"

    # Ensure unique OAuth accounts (only when provider_id is set)
    create unique_index(:users, [:provider, :provider_id], where: "provider_id IS NOT NULL")
  end
end
