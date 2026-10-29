defmodule Firmowid.Repo.Migrations.DropAshSegmentFromStoredModuleNames do
  @moduledoc """
  Renames module names stored in the database after the domain modules moved from
  `Firmowid.Ash.*` to `Firmowid.*`. Oban runs a job only while its worker module
  exists, AshOban signal jobs keep their resource and signal modules in `args`,
  and Ash reads `ash_events.resource` back with `String.to_existing_atom/1`.

  A data-only migration: Ash codegen generates schema changes only.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE oban.oban_jobs
    SET worker = regexp_replace(worker, '^Firmowid\\.Ash\\.', 'Firmowid.'),
        args = replace(args::text, '"Elixir.Firmowid.Ash.', '"Elixir.Firmowid.')::jsonb
    WHERE worker LIKE 'Firmowid.Ash.%' OR args::text LIKE '%"Elixir.Firmowid.Ash.%'
    """)

    execute("""
    UPDATE ash_events
    SET resource = regexp_replace(resource, '^Elixir\\.Firmowid\\.Ash\\.', 'Elixir.Firmowid.')
    WHERE resource LIKE 'Elixir.Firmowid.Ash.%'
    """)
  end

  def down do
    execute("""
    UPDATE oban.oban_jobs
    SET worker = regexp_replace(worker, '^Firmowid\\.(?!Ash\\.)', 'Firmowid.Ash.'),
        args = regexp_replace(args::text, '"Elixir\\.Firmowid\\.(?!Ash\\.)', '"Elixir.Firmowid.Ash.', 'g')::jsonb
    WHERE (worker LIKE 'Firmowid.%' AND worker NOT LIKE 'Firmowid.Ash.%')
       OR args::text ~ '"Elixir\\.Firmowid\\.(?!Ash\\.)'
    """)

    execute("""
    UPDATE ash_events
    SET resource = regexp_replace(resource, '^Elixir\\.Firmowid\\.', 'Elixir.Firmowid.Ash.')
    WHERE resource LIKE 'Elixir.Firmowid.%' AND resource NOT LIKE 'Elixir.Firmowid.Ash.%'
    """)
  end
end
