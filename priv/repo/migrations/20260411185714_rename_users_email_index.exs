defmodule Firmowid.Repo.Migrations.RenameUsersEmailIndex do
  @moduledoc """
  Renames the legacy `users_email_index` to `users_unique_email_index` to match
  the naming convention that AshPostgres generates for the `unique_email` identity.

  This allows removing the `identity_index_names` mapping from the postgres block
  in the User resource, eliminating custom configuration that worked around the
  pre-Ash index name.
  """
  use Ecto.Migration

  def up do
    execute "ALTER INDEX users_email_index RENAME TO users_unique_email_index"
  end

  def down do
    execute "ALTER INDEX users_unique_email_index RENAME TO users_email_index"
  end
end
