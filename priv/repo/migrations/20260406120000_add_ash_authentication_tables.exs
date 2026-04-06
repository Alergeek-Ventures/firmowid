defmodule Firmowid.Repo.Migrations.AddAshAuthenticationTables do
  @moduledoc """
  Adds token and user identity tables for ash_authentication.

  - `tokens` — stores JWTs for session revocation, password reset, confirmation.
    Uses `jti` (JWT ID) as primary key, no surrogate UUID.
  - `user_identities` — stores OAuth provider links (replaces `google_provider_id`
    column on users table).
  - Drops `users_tokens` — the legacy phx.gen.auth token table. All active
    sessions are invalidated on deploy.
  """
  use Ecto.Migration

  def change do
    create table(:tokens, primary_key: false) do
      add :jti, :text, null: false, primary_key: true
      add :subject, :text, null: false
      add :expires_at, :utc_datetime, null: false
      add :purpose, :text, null: false
      add :extra_data, :map

      timestamps(type: :utc_datetime_usec)
    end

    create table(:user_identities, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :strategy, :text, null: false
      add :uid, :text, null: false
      add :access_token, :text
      add :access_token_expires_at, :utc_datetime
      add :refresh_token, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_identities, [:strategy, :uid])
    create index(:user_identities, [:user_id])

    # Add email_change_confirmed_at for the confirm_email_update add-on
    alter table(:users) do
      add :email_change_confirmed_at, :utc_datetime
    end

    drop table(:users_tokens)
  end
end
