defmodule Firmowid.Repo.Migrations.AddErrorTracker do
  use Ecto.Migration

  def up, do: ErrorTracker.Migration.up(version: 5)

  def down, do: ErrorTracker.Migration.down(version: 1)
end
