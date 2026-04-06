defmodule Firmowid.Repo.Migrations.MigrateGoogleIdentitiesAndDropColumns do
  @moduledoc """
  Two-part migration:

  1. Data migration — copy `google_provider_id` from `users` into `user_identities`
     so that existing Google-linked accounts continue working under
     `AshAuthentication.UserIdentity` (which replaced the legacy columns).
     The insert is idempotent: skipped if a matching identity already exists.

  2. Schema cleanup — drop the now-dead columns `google_provider_id`, `provider`,
     and `provider_id` from the `users` table.
  """
  use Ecto.Migration

  def up do
    # 1. Copy existing Google links into user_identities.
    #    UserIdentity attributes: user_id, uid (provider's user ID), strategy (strategy name).
    #    Only insert for users that have a google_provider_id and don't already
    #    have a matching identity (idempotent).
    execute """
    INSERT INTO user_identities (id, user_id, uid, strategy, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      u.id,
      u.google_provider_id,
      'google',
      NOW(),
      NOW()
    FROM users u
    WHERE u.google_provider_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM user_identities ui
        WHERE ui.user_id = u.id AND ui.strategy = 'google'
      )
    """

    # 2. Drop the dead columns.
    alter table(:users) do
      remove :google_provider_id
      remove :provider
      remove :provider_id
    end
  end

  def down do
    alter table(:users) do
      add :google_provider_id, :string
      add :provider, :string, default: "password"
      add :provider_id, :string
    end

    # Restore google_provider_id from user_identities.
    execute """
    UPDATE users u
    SET google_provider_id = ui.uid
    FROM user_identities ui
    WHERE ui.user_id = u.id AND ui.strategy = 'google'
    """
  end
end
