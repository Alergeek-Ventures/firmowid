defmodule Firmowid.Repo.Migrations.AddStateToRequisitions do
  @moduledoc """
  Adds state column for AshStateMachine support.

  AshStateMachine requires a `state` attribute to track state transitions.
  We migrate existing data from the `status` enum column.
  """
  use Ecto.Migration

  def up do
    # Add state column as string (AshStateMachine uses atom values stored as strings)
    alter table(:requisitions) do
      add :state, :string, null: true
    end

    # Migrate existing status values to state
    execute """
    UPDATE requisitions
    SET state = status::text
    """

    # Make state non-nullable after migration
    alter table(:requisitions) do
      modify :state, :string, null: false
    end

    # Add index for efficient state-based queries (used by AshOban trigger)
    create index(:requisitions, [:state, :organization_id])
  end

  def down do
    drop index(:requisitions, [:state, :organization_id])

    alter table(:requisitions) do
      remove :state
    end
  end
end
