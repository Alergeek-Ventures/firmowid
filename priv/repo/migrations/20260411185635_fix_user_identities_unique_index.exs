defmodule Firmowid.Repo.Migrations.FixUserIdentitiesUniqueIndex do
  @moduledoc """
  Replaces the legacy (strategy, uid) unique index on user_identities with the
  (strategy, uid, user_id) index that AshAuthentication.UserIdentity requires for its
  upsert identity `unique_on_strategy_and_uid_and_user_id`.

  The old index only covered (strategy, uid), which prevented ON CONFLICT from matching
  when Ash issued `ON CONFLICT (strategy, uid, user_id)` — causing a Postgres 42P10 error
  on every Google sign-in attempt.
  """
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:user_identities, [:strategy, :uid],
                     name: "user_identities_strategy_uid_index"
                   )

    create unique_index(:user_identities, [:strategy, :uid, :user_id],
             name: "user_identities_unique_on_strategy_and_uid_and_user_id_index"
           )
  end

  def down do
    drop_if_exists unique_index(:user_identities, [:strategy, :uid, :user_id],
                     name: "user_identities_unique_on_strategy_and_uid_and_user_id_index"
                   )

    create unique_index(:user_identities, [:strategy, :uid],
             name: "user_identities_strategy_uid_index"
           )
  end
end
