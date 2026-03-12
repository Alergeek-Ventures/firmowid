defmodule Firmowid.Repo.Migrations.AddTagKindsAndUpdateConstraints do
  @moduledoc """
  Adds `kind` enum column to `entity_tags`, makes `tag_definition_id` nullable,
  replaces old triggers with new taggability and category exclusivity checks,
  adds ON DELETE CASCADE to the `tag_definition_id` FK, and backfills
  `TagDefinition` rows for existing projects that lack one.
  """
  use Ecto.Migration

  @project_tag_colors ~w(#2563EB #059669 #D97706 #7C3AED #DB2777 #0891B2 #4F46E5 #DC2626 #65A30D #0D9488)

  def up do
    # 1. Add kind column to entity_tags (default 'project' for existing rows)
    execute "CREATE TYPE entity_tag_kind AS ENUM ('project', 'company', 'internal')"

    alter table(:entity_tags) do
      add :kind, :entity_tag_kind, null: false, default: "project"
    end

    # 2. Make tag_definition_id nullable (was NOT NULL)
    alter table(:entity_tags) do
      modify :tag_definition_id, :binary_id, null: true
    end

    # 3. Add CHECK: kind and tag_definition_id must be consistent
    create constraint(:entity_tags, :entity_tags_kind_tag_definition_check,
             check: """
             (kind = 'project' AND tag_definition_id IS NOT NULL)
             OR (kind != 'project' AND tag_definition_id IS NULL)
             """
           )

    # 4. Update entity_type CHECK — remove join-table types
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS tagged_items_entity_type_check"
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS entity_tags_entity_type_check"

    create constraint(:entity_tags, :entity_tags_entity_type_check,
             check: "entity_type IN ('transaction', 'sales_invoice', 'cost_invoice')"
           )

    # 5. Drop old unique index, add new partial indexes
    drop_if_exists unique_index(:entity_tags, [:entity_type, :entity_id, :tag_definition_id])

    # For project tags: same project tag can't be assigned twice to same entity
    create unique_index(:entity_tags, [:entity_type, :entity_id, :tag_definition_id],
             where: "tag_definition_id IS NOT NULL",
             name: :entity_tags_project_unique
           )

    # For built-in kinds: only one company or one internal per entity
    create unique_index(:entity_tags, [:entity_type, :entity_id, :kind],
             where: "kind != 'project'",
             name: :entity_tags_builtin_kind_unique
           )

    # 6. Replace tag_definition_id FK with ON DELETE CASCADE
    #    The FK may exist under the old table name (tagged_items)
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS tagged_items_tag_id_fkey"
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS entity_tags_tag_definition_id_fkey"

    alter table(:entity_tags) do
      modify :tag_definition_id,
             references(:tag_definitions, type: :binary_id, on_delete: :delete_all)
    end

    # 7. Drop old linking consistency triggers (matching and tagging are now orthogonal)
    execute "DROP TRIGGER IF EXISTS cost_linking_consistency_trigger ON cost_invoices_transactions"

    execute "DROP TRIGGER IF EXISTS sales_linking_consistency_trigger ON sales_invoices_transactions"

    execute "DROP FUNCTION IF EXISTS check_cost_linking_consistency() CASCADE"
    execute "DROP FUNCTION IF EXISTS check_sales_linking_consistency() CASCADE"

    # 8. Drop old tag consistency trigger
    execute "DROP TRIGGER IF EXISTS tag_consistency_trigger ON entity_tags"
    execute "DROP FUNCTION IF EXISTS check_tag_consistency() CASCADE"

    # 9. Create new trigger: only matched or skipped entities can be tagged
    execute """
    CREATE OR REPLACE FUNCTION check_entity_taggable() RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.entity_type = 'transaction' THEN
        IF NOT EXISTS (
          SELECT 1 FROM transactions t WHERE t.id = NEW.entity_id AND t.skip_invoicing = true
        ) AND NOT EXISTS (
          SELECT 1 FROM cost_invoices_transactions cit WHERE cit.transaction_id = NEW.entity_id
        ) AND NOT EXISTS (
          SELECT 1 FROM sales_invoices_transactions sit WHERE sit.transaction_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot tag a transaction that is neither matched nor skipped';
        END IF;
      END IF;

      IF NEW.entity_type = 'sales_invoice' THEN
        IF NOT EXISTS (
          SELECT 1 FROM sales_invoices si WHERE si.id = NEW.entity_id AND si.skip_invoicing = true
        ) AND NOT EXISTS (
          SELECT 1 FROM sales_invoices_transactions sit WHERE sit.sales_invoice_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot tag a sales invoice that is neither matched nor skipped';
        END IF;
      END IF;

      IF NEW.entity_type = 'cost_invoice' THEN
        IF NOT EXISTS (
          SELECT 1 FROM cost_invoices ci WHERE ci.id = NEW.entity_id AND ci.skip_invoicing = true
        ) AND NOT EXISTS (
          SELECT 1 FROM cost_invoices_transactions cit WHERE cit.cost_invoice_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot tag a cost invoice that is neither matched nor skipped';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER entity_taggable_trigger
      BEFORE INSERT ON entity_tags
      FOR EACH ROW
      EXECUTE FUNCTION check_entity_taggable();
    """

    # 10. Create new trigger: category exclusivity
    execute """
    CREATE OR REPLACE FUNCTION check_entity_tag_category_exclusivity() RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.kind = 'project' THEN
        IF EXISTS (
          SELECT 1 FROM entity_tags et
          WHERE et.entity_type = NEW.entity_type
            AND et.entity_id = NEW.entity_id
            AND et.kind != 'project'
        ) THEN
          RAISE EXCEPTION 'Cannot add project tag: entity already has a built-in category (company or internal)';
        END IF;
      ELSE
        -- kind is company or internal
        IF EXISTS (
          SELECT 1 FROM entity_tags et
          WHERE et.entity_type = NEW.entity_type
            AND et.entity_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot set built-in category: entity already has tags assigned';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER entity_tag_category_exclusivity_trigger
      BEFORE INSERT ON entity_tags
      FOR EACH ROW
      EXECUTE FUNCTION check_entity_tag_category_exclusivity();
    """

    # 11. Backfill TagDefinitions for existing projects
    flush()
    backfill_project_tag_definitions()
  end

  def down do
    # Drop new triggers
    execute "DROP TRIGGER IF EXISTS entity_tag_category_exclusivity_trigger ON entity_tags"
    execute "DROP FUNCTION IF EXISTS check_entity_tag_category_exclusivity() CASCADE"
    execute "DROP TRIGGER IF EXISTS entity_taggable_trigger ON entity_tags"
    execute "DROP FUNCTION IF EXISTS check_entity_taggable() CASCADE"

    # Drop new indexes
    drop_if_exists index(:entity_tags, [:entity_type, :entity_id, :kind],
                     name: :entity_tags_builtin_kind_unique
                   )

    drop_if_exists index(:entity_tags, [:entity_type, :entity_id, :tag_definition_id],
                     name: :entity_tags_project_unique
                   )

    # Restore old unique index
    create unique_index(:entity_tags, [:entity_type, :entity_id, :tag_definition_id])

    # Drop new constraints
    drop constraint(:entity_tags, :entity_tags_entity_type_check)
    drop constraint(:entity_tags, :entity_tags_kind_tag_definition_check)

    # Replace cascade FK with plain FK
    drop constraint(:entity_tags, "entity_tags_tag_definition_id_fkey")

    alter table(:entity_tags) do
      modify :tag_definition_id,
             references(:tag_definitions, type: :binary_id, on_delete: :nothing),
             from: references(:tag_definitions, type: :binary_id, on_delete: :delete_all)
    end

    # Restore old entity_type constraint (with join-table types)
    create constraint(:entity_tags, :tagged_items_entity_type_check,
             check:
               "entity_type IN ('transaction', 'sales_invoice', 'cost_invoice', 'cost_invoices_transactions', 'sales_invoices_transactions')"
           )

    # Delete any non-project entity_tags (they have NULL tag_definition_id)
    execute "DELETE FROM entity_tags WHERE kind != 'project'"

    # Make tag_definition_id NOT NULL again
    alter table(:entity_tags) do
      modify :tag_definition_id, :binary_id, null: false
    end

    # Remove kind column
    alter table(:entity_tags) do
      remove :kind
    end

    execute "DROP TYPE IF EXISTS entity_tag_kind"

    # Restore old triggers
    execute """
    CREATE OR REPLACE FUNCTION check_tag_consistency() RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.entity_type = 'transaction' THEN
        IF EXISTS (
          SELECT 1 FROM cost_invoices_transactions cit
          WHERE cit.transaction_id = NEW.entity_id
        ) OR EXISTS (
          SELECT 1 FROM sales_invoices_transactions sit
          WHERE sit.transaction_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot tag a transaction that is linked to an invoice';
        END IF;
      END IF;

      IF NEW.entity_type = 'cost_invoice' THEN
        IF EXISTS (
          SELECT 1 FROM cost_invoices_transactions cit
          WHERE cit.cost_invoice_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot tag a cost invoice that is linked to a transaction';
        END IF;
      END IF;

      IF NEW.entity_type = 'sales_invoice' THEN
        IF EXISTS (
          SELECT 1 FROM sales_invoices_transactions sit
          WHERE sit.sales_invoice_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot tag a sales invoice that is linked to a transaction';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER tag_consistency_trigger
      BEFORE INSERT ON entity_tags
      FOR EACH ROW
      EXECUTE FUNCTION check_tag_consistency();
    """

    execute """
    CREATE OR REPLACE FUNCTION check_cost_linking_consistency() RETURNS TRIGGER AS $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM entity_tags ti
        WHERE ti.entity_id = NEW.transaction_id
        AND ti.entity_type = 'transaction'
      ) THEN
        RAISE EXCEPTION 'Cannot link a transaction that has tags';
      END IF;

      IF EXISTS (
        SELECT 1 FROM entity_tags ti
        WHERE ti.entity_id = NEW.cost_invoice_id
        AND ti.entity_type = 'cost_invoice'
      ) THEN
        RAISE EXCEPTION 'Cannot link a cost invoice that has tags';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER cost_linking_consistency_trigger
      BEFORE INSERT ON cost_invoices_transactions
      FOR EACH ROW
      EXECUTE FUNCTION check_cost_linking_consistency();
    """

    execute """
    CREATE OR REPLACE FUNCTION check_sales_linking_consistency() RETURNS TRIGGER AS $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM entity_tags ti
        WHERE ti.entity_id = NEW.transaction_id
        AND ti.entity_type = 'transaction'
      ) THEN
        RAISE EXCEPTION 'Cannot link a transaction that has tags';
      END IF;

      IF EXISTS (
        SELECT 1 FROM entity_tags ti
        WHERE ti.entity_id = NEW.sales_invoice_id
        AND ti.entity_type = 'sales_invoice'
      ) THEN
        RAISE EXCEPTION 'Cannot link a sales invoice that has tags';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER sales_linking_consistency_trigger
      BEFORE INSERT ON sales_invoices_transactions
      FOR EACH ROW
      EXECUTE FUNCTION check_sales_linking_consistency();
    """
  end

  # Backfills TagDefinitions for existing projects that don't have one.
  # Uses raw SQL because migration code should not depend on application schemas
  # (which may change after the migration is written).
  defp backfill_project_tag_definitions do
    %{rows: rows} =
      repo().query!(
        "SELECT id, name, organization_id FROM projects WHERE tag_definition_id IS NULL",
        []
      )

    rows
    |> Enum.with_index()
    |> Enum.each(fn {[project_id, name, org_id], index} ->
      # Reuse existing tag_definition if name+org matches
      %{rows: existing} =
        repo().query!(
          "SELECT id FROM tag_definitions WHERE name = $1 AND organization_id = $2",
          [name, org_id]
        )

      tag_id =
        case existing do
          [[existing_id]] ->
            existing_id

          _ ->
            color = Enum.at(@project_tag_colors, rem(index, length(@project_tag_colors)))
            now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            {:ok, new_id} = Ecto.UUID.dump(Ecto.UUID.generate())

            repo().query!(
              """
              INSERT INTO tag_definitions (id, name, color, organization_id, inserted_at, updated_at)
              VALUES ($1, $2, $3, $4, $5, $6)
              """,
              [new_id, name, color, org_id, now, now]
            )

            new_id
        end

      repo().query!("UPDATE projects SET tag_definition_id = $1 WHERE id = $2", [
        tag_id,
        project_id
      ])
    end)
  end
end
