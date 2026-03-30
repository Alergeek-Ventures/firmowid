defmodule Firmowid.Repo.Migrations.UpgradeObanToV14 do
  @moduledoc """
  Upgrades Oban schema from v12 to v14.

  v13 and v14 add the `suspended` value to the `oban_job_state` enum,
  which is required by Oban 2.21+.
  """

  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14, prefix: "oban")
  def down, do: Oban.Migration.down(version: 12, prefix: "oban")
end
