defmodule Firmowid.Repo.Migrations.AddSessionOverlapConstraint do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION prevent_session_overlap()
    RETURNS TRIGGER AS $$
    DECLARE
      new_start timestamp := NEW.start_datetime;
      new_end timestamp := NEW.end_datetime;
    BEGIN
      IF EXISTS (
        SELECT 1 FROM sessions
        WHERE user_id = NEW.user_id
          AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000')
          AND (
            -- Overlap logic for all cases (including NULL end_datetime)
            (start_datetime < COALESCE(new_end, 'infinity') AND COALESCE(end_datetime, 'infinity') > new_start)
          )
      ) THEN
        RAISE EXCEPTION 'Session for this user overlaps with an existing session.';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER no_session_overlap_trigger
    BEFORE INSERT OR UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION prevent_session_overlap();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS no_session_overlap_trigger ON sessions;"
    execute "DROP FUNCTION IF EXISTS prevent_session_overlap();"
  end
end
