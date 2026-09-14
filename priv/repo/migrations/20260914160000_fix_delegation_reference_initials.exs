defmodule Firmowid.Repo.Migrations.FixDelegationReferenceInitials do
  @moduledoc "Fixes delegation reference initials for multi-word user names."

  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION assign_delegation_reference()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      initials text;
      sequence_number integer;
    BEGIN
      SELECT upper(string_agg(left(word, 1), ''))
      INTO initials
      FROM unnest(
        string_to_array(
          regexp_replace(
            coalesce((SELECT name FROM public.users WHERE id = NEW.user_id), ''),
            E'\\s+',
            ' ',
            'g'
          ),
          ' '
        )
      ) AS words(word)
      WHERE word <> '';

      initials := coalesce(
        nullif(initials, ''),
        'U' || upper(left((SELECT id::text FROM public.users WHERE id = NEW.user_id), 8))
      );

      PERFORM pg_advisory_xact_lock(
        hashtextextended(
          NEW.organization_id::text || ':' || NEW.user_id::text || ':' || to_char(NEW.billing_month, 'YYYY-MM'),
          0
        )
      );

      SELECT coalesce(max((regexp_match(reference, '-(\\d+)$'))[1]::integer), 0) + 1
      INTO sequence_number
      FROM delegations
      WHERE organization_id = NEW.organization_id
        AND user_id = NEW.user_id
        AND billing_month = NEW.billing_month;

      IF NEW.reference IS NULL OR NEW.reference = '' OR NEW.reference = 'pending' THEN
        NEW.reference := initials || '-' || to_char(NEW.billing_month, 'YYYY-MM') || '-' || sequence_number;
      END IF;
      RETURN NEW;
    END;
    $$;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION assign_delegation_reference()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      initials text;
      sequence_number integer;
    BEGIN
      SELECT upper(string_agg(left(word, 1), ''))
      INTO initials
      FROM regexp_split_to_table(
        coalesce((SELECT name FROM public.users WHERE id = NEW.user_id), ''),
        E'\\s+'
      ) AS words(word)
      WHERE word <> '';

      initials := coalesce(
        nullif(initials, ''),
        'U' || upper(left((SELECT id::text FROM public.users WHERE id = NEW.user_id), 8))
      );

      PERFORM pg_advisory_xact_lock(
        hashtextextended(
          NEW.organization_id::text || ':' || NEW.user_id::text || ':' || to_char(NEW.billing_month, 'YYYY-MM'),
          0
        )
      );

      SELECT coalesce(max((regexp_match(reference, '-(\\d+)$'))[1]::integer), 0) + 1
      INTO sequence_number
      FROM delegations
      WHERE organization_id = NEW.organization_id
        AND user_id = NEW.user_id
        AND billing_month = NEW.billing_month;

      IF NEW.reference IS NULL OR NEW.reference = '' OR NEW.reference = 'pending' THEN
        NEW.reference := initials || '-' || to_char(NEW.billing_month, 'YYYY-MM') || '-' || sequence_number;
      END IF;
      RETURN NEW;
    END;
    $$;
    """)
  end
end
