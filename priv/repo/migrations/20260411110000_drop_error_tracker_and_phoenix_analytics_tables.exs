defmodule Firmowid.Repo.Migrations.DropErrorTrackerAndPhoenixAnalyticsTables do
  use Ecto.Migration

  def up do
    drop_if_exists table(:error_tracker_occurrences)
    drop_if_exists table(:error_tracker_errors)
    drop_if_exists table(:error_tracker_meta)
    execute("DROP TABLE IF EXISTS requests")
  end

  def down do
    raise "Irreversible migration"
  end
end
