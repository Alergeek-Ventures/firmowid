defmodule Firmowid.Repo.Migrations.SplitEntityTagsIntoPolymorphicTables do
  @moduledoc """
  Splits the monolithic `entity_tags` table into 3 per-entity-type tables
  with proper FK constraints and ON DELETE CASCADE.

  New tables:
    - `sales_invoice_entity_tags` (FK → sales_invoices.id)
    - `cost_invoice_entity_tags`  (FK → cost_invoices.id)
    - `transaction_entity_tags`   (FK → transactions.id)

  Each table uses `resource_id` (instead of `entity_id`) as the FK column,
  dropping the `entity_type` discriminator entirely. Indexes and constraints
  mirror the old table's structure but are simpler per-table.

  DB triggers (taggability check, category exclusivity) are rewritten per-table —
  each can use a direct FK join instead of dispatching on `entity_type`.

  The old `entity_tags` table and its triggers are dropped at the end.
  """
  use Ecto.Migration

  @entity_tables [
    {:sales_invoice, "sales_invoice_entity_tags", "sales_invoices", "sales_invoices_transactions",
     "sales_invoice_id"},
    {:cost_invoice, "cost_invoice_entity_tags", "cost_invoices", "cost_invoices_transactions",
     "cost_invoice_id"},
    {:transaction, "transaction_entity_tags", "transactions", nil, nil}
  ]

  def up do
    # ── 1. Create the 3 new tables ──────────────────────────────────────

    for {_type, table_name, parent_table, _join_table, _join_col} <- @entity_tables do
      create table(table_name, primary_key: false) do
        add :id, :binary_id, primary_key: true
        add :kind, :entity_tag_kind, null: false, default: "project"

        add :resource_id,
            references(parent_table, type: :binary_id, on_delete: :delete_all),
            null: false

        add :tag_definition_id,
            references(:tag_definitions, type: :binary_id, on_delete: :delete_all)

        add :organization_id,
            references(:organizations, type: :binary_id, on_delete: :delete_all),
            null: false

        timestamps(type: :utc_datetime)
      end

      # For project tags: same tag can't be assigned twice to same entity
      create unique_index(table_name, [:resource_id, :tag_definition_id],
               where: "tag_definition_id IS NOT NULL",
               name: "#{table_name}_project_unique"
             )

      # For built-in kinds: only one company or one internal per entity
      create unique_index(table_name, [:resource_id, :kind],
               where: "kind != 'project'",
               name: "#{table_name}_builtin_kind_unique"
             )

      # kind ↔ tag_definition_id consistency
      create constraint(table_name, "#{table_name}_kind_tag_definition_check",
               check: """
               (kind = 'project' AND tag_definition_id IS NOT NULL)
               OR (kind != 'project' AND tag_definition_id IS NULL)
               """
             )

      # Index on organization_id for multitenancy queries
      create index(table_name, [:organization_id])
    end

    # ── 2. Copy data from entity_tags into the new tables ───────────────

    for {type, table_name, _parent_table, _join_table, _join_col} <- @entity_tables do
      execute """
      INSERT INTO #{table_name} (id, kind, resource_id, tag_definition_id, organization_id, inserted_at, updated_at)
      SELECT id, kind, entity_id, tag_definition_id, organization_id, inserted_at, updated_at
      FROM entity_tags
      WHERE entity_type = '#{type}'
      """
    end

    # ── 3. Drop old triggers on entity_tags ─────────────────────────────

    execute "DROP TRIGGER IF EXISTS entity_tag_category_exclusivity_trigger ON entity_tags"
    execute "DROP TRIGGER IF EXISTS entity_taggable_trigger ON entity_tags"

    # ── 4. Create per-table taggability triggers ────────────────────────

    # Sales invoices: must be matched or skipped
    execute """
    CREATE OR REPLACE FUNCTION check_sales_invoice_entity_tag_taggable() RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM sales_invoices si WHERE si.id = NEW.resource_id AND si.skip_invoicing = true
      ) AND NOT EXISTS (
        SELECT 1 FROM sales_invoices_transactions sit WHERE sit.sales_invoice_id = NEW.resource_id
      ) THEN
        RAISE EXCEPTION 'Cannot tag a sales invoice that is neither matched nor skipped';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER sales_invoice_entity_tag_taggable_trigger
      BEFORE INSERT ON sales_invoice_entity_tags
      FOR EACH ROW
      EXECUTE FUNCTION check_sales_invoice_entity_tag_taggable();
    """

    # Cost invoices: must be matched or skipped
    execute """
    CREATE OR REPLACE FUNCTION check_cost_invoice_entity_tag_taggable() RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM cost_invoices ci WHERE ci.id = NEW.resource_id AND ci.skip_invoicing = true
      ) AND NOT EXISTS (
        SELECT 1 FROM cost_invoices_transactions cit WHERE cit.cost_invoice_id = NEW.resource_id
      ) THEN
        RAISE EXCEPTION 'Cannot tag a cost invoice that is neither matched nor skipped';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER cost_invoice_entity_tag_taggable_trigger
      BEFORE INSERT ON cost_invoice_entity_tags
      FOR EACH ROW
      EXECUTE FUNCTION check_cost_invoice_entity_tag_taggable();
    """

    # Transactions: must be skip_invoicing=true (matched check is via join tables)
    execute """
    CREATE OR REPLACE FUNCTION check_transaction_entity_tag_taggable() RETURNS TRIGGER AS $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM transactions t WHERE t.id = NEW.resource_id AND t.skip_invoicing = true
      ) AND NOT EXISTS (
        SELECT 1 FROM cost_invoices_transactions cit WHERE cit.transaction_id = NEW.resource_id
      ) AND NOT EXISTS (
        SELECT 1 FROM sales_invoices_transactions sit WHERE sit.transaction_id = NEW.resource_id
      ) THEN
        RAISE EXCEPTION 'Cannot tag a transaction that is neither matched nor skipped';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER transaction_entity_tag_taggable_trigger
      BEFORE INSERT ON transaction_entity_tags
      FOR EACH ROW
      EXECUTE FUNCTION check_transaction_entity_tag_taggable();
    """

    # ── 5. Create per-table category exclusivity triggers ───────────────

    for {_type, table_name, _parent_table, _join_table, _join_col} <- @entity_tables do
      fn_name = "check_#{table_name}_category_exclusivity"

      execute """
      CREATE OR REPLACE FUNCTION #{fn_name}() RETURNS TRIGGER AS $$
      BEGIN
        IF NEW.kind = 'project' THEN
          IF EXISTS (
            SELECT 1 FROM #{table_name} et
            WHERE et.resource_id = NEW.resource_id
              AND et.kind != 'project'
          ) THEN
            RAISE EXCEPTION 'Cannot add project tag: entity already has a built-in category (company or internal)';
          END IF;
        ELSE
          IF EXISTS (
            SELECT 1 FROM #{table_name} et
            WHERE et.resource_id = NEW.resource_id
          ) THEN
            RAISE EXCEPTION 'Cannot set built-in category: entity already has tags assigned';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """

      execute """
      CREATE TRIGGER #{table_name}_category_exclusivity_trigger
        BEFORE INSERT ON #{table_name}
        FOR EACH ROW
        EXECUTE FUNCTION #{fn_name}();
      """
    end

    # ── 6. Drop the old entity_tags table ───────────────────────────────

    drop table(:entity_tags)

    # ── 7. Drop old trigger functions (no longer needed) ────────────────

    execute "DROP FUNCTION IF EXISTS check_entity_taggable() CASCADE"
    execute "DROP FUNCTION IF EXISTS check_entity_tag_category_exclusivity() CASCADE"

    # Drop the entity_tag_kind enum type is NOT needed — the new tables reuse it
  end

  def down do
    # ── Recreate entity_tags table ──────────────────────────────────────

    create table(:entity_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :entity_tag_kind, null: false, default: "project"
      add :entity_type, :string, null: false
      add :entity_id, :binary_id, null: false

      add :tag_definition_id,
          references(:tag_definitions, type: :binary_id, on_delete: :delete_all)

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:entity_tags, :entity_tags_entity_type_check,
             check: "entity_type IN ('transaction', 'sales_invoice', 'cost_invoice')"
           )

    create constraint(:entity_tags, :entity_tags_kind_tag_definition_check,
             check: """
             (kind = 'project' AND tag_definition_id IS NOT NULL)
             OR (kind != 'project' AND tag_definition_id IS NULL)
             """
           )

    create unique_index(:entity_tags, [:entity_type, :entity_id, :tag_definition_id],
             where: "tag_definition_id IS NOT NULL",
             name: :entity_tags_project_unique
           )

    create unique_index(:entity_tags, [:entity_type, :entity_id, :kind],
             where: "kind != 'project'",
             name: :entity_tags_builtin_kind_unique
           )

    # ── Copy data back ──────────────────────────────────────────────────

    for {type, table_name, _parent_table, _join_table, _join_col} <- @entity_tables do
      execute """
      INSERT INTO entity_tags (id, kind, entity_type, entity_id, tag_definition_id, organization_id, inserted_at, updated_at)
      SELECT id, kind, '#{type}', resource_id, tag_definition_id, organization_id, inserted_at, updated_at
      FROM #{table_name}
      """
    end

    # ── Recreate old triggers ───────────────────────────────────────────

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

    # ── Drop new per-table triggers and tables ──────────────────────────

    for {_type, table_name, _parent_table, _join_table, _join_col} <- @entity_tables do
      execute "DROP TRIGGER IF EXISTS #{table_name}_category_exclusivity_trigger ON #{table_name}"
      execute "DROP FUNCTION IF EXISTS check_#{table_name}_category_exclusivity() CASCADE"
      execute "DROP TRIGGER IF EXISTS #{table_name}_taggable_trigger ON #{table_name}"
    end

    execute "DROP FUNCTION IF EXISTS check_sales_invoice_entity_tag_taggable() CASCADE"
    execute "DROP FUNCTION IF EXISTS check_cost_invoice_entity_tag_taggable() CASCADE"
    execute "DROP FUNCTION IF EXISTS check_transaction_entity_tag_taggable() CASCADE"

    for {_type, table_name, _parent_table, _join_table, _join_col} <- @entity_tables do
      drop table(table_name)
    end
  end
end
