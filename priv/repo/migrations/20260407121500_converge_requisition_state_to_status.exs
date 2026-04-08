defmodule Firmowid.Repo.Migrations.ConvergeRequisitionStateToStatus do
  @moduledoc """
  Converges requisitions state storage to `status` only.

  This migration is intentionally idempotent:
  - On environments that still have `requisitions.state`, it removes it.
  - On environments that never had `state`, it is a no-op.
  """
  use Ecto.Migration

  def up do
    execute("DROP INDEX IF EXISTS requisitions_state_organization_id_index")
    execute("ALTER TABLE requisitions DROP COLUMN IF EXISTS state")
  end

  def down do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'requisitions'
          AND column_name = 'state'
      ) THEN
        ALTER TABLE requisitions ADD COLUMN state varchar;
        UPDATE requisitions SET state = status::text;
        ALTER TABLE requisitions ALTER COLUMN state SET NOT NULL;
      END IF;
    END
    $$;
    """)

    execute(
      "CREATE INDEX IF NOT EXISTS requisitions_state_organization_id_index ON requisitions (state, organization_id)"
    )
  end
end
