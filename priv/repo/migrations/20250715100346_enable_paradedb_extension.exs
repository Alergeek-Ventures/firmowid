defmodule Firmowid.Repo.Migrations.EnableParadedbExtension do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
  end
end
