defmodule Firmowid.Repo.Migrations.CreateAshEvents do
  @moduledoc """
  Creates the ash_events table for AshEvents event log.

  Used by BankAccount to derive sync status (broken?, has_successful_sync?)
  without querying Oban jobs directly.
  """
  use Ecto.Migration

  def change do
    create table(:ash_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :record_id, :uuid, null: false
      add :version, :bigint, null: false, default: 1
      add :metadata, :map, null: false, default: %{}
      add :data, :map, null: false, default: %{}
      add :changed_attributes, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
      add :resource, :text, null: false
      add :action, :text, null: false
      add :action_type, :text, null: false
    end

    create index(:ash_events, [:record_id])
    create index(:ash_events, [:resource, :action])
  end
end
