defmodule Firmowid.Repo.Migrations.RenameTagsAndTaggedItems do
  use Ecto.Migration

  def up do
    # Drop triggers on old table before renaming
    execute "DROP TRIGGER IF EXISTS tag_consistency_trigger ON tagged_items"

    # Rename tables
    rename table(:tags), to: table(:tag_definitions)
    rename table(:tagged_items), to: table(:entity_tags)

    # Rename foreign key columns
    rename table(:entity_tags), :tag_id, to: :tag_definition_id
    rename table(:projects), :tag_id, to: :tag_definition_id

    # Update constraints
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS tagged_items_entity_type_check"
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS entity_tags_entity_type_check"

    create constraint(:entity_tags, :entity_tags_entity_type_check,
             check:
               "entity_type IN ('transaction', 'sales_invoice', 'cost_invoice', 'cost_invoices_transactions', 'sales_invoices_transactions')"
           )

    # Update functions to refer to entity_tags instead of tagged_items
    execute """
    CREATE OR REPLACE FUNCTION check_cost_linking_consistency() RETURNS TRIGGER AS $$
    BEGIN
      -- Check if transaction has tags
      IF EXISTS (
        SELECT 1 FROM entity_tags ti 
        WHERE ti.entity_id = NEW.transaction_id 
          AND ti.entity_type = 'transaction'
      ) THEN
        RAISE EXCEPTION 'Cannot link a transaction that has tags';
      END IF;

      -- Check if cost invoice has tags
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
    CREATE OR REPLACE FUNCTION check_sales_linking_consistency() RETURNS TRIGGER AS $$
    BEGIN
      -- Check if transaction has tags
      IF EXISTS (
        SELECT 1 FROM entity_tags ti 
        WHERE ti.entity_id = NEW.transaction_id 
          AND ti.entity_type = 'transaction'
      ) THEN
        RAISE EXCEPTION 'Cannot link a transaction that has tags';
      END IF;

      -- Check if sales invoice has tags
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

    # Recreate trigger on new table
    execute """
    CREATE TRIGGER tag_consistency_trigger
      BEFORE INSERT ON entity_tags
      FOR EACH ROW
      EXECUTE FUNCTION check_tag_consistency();
    """
  end

  def down do
    # Drop trigger on new table
    execute "DROP TRIGGER IF EXISTS tag_consistency_trigger ON entity_tags"

    # Revert constraint name/content
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS entity_tags_entity_type_check"
    execute "ALTER TABLE entity_tags DROP CONSTRAINT IF EXISTS tagged_items_entity_type_check"

    create constraint(:entity_tags, :tagged_items_entity_type_check,
             check: "entity_type IN ('transaction', 'sales_invoice', 'cost_invoice')"
           )

    # Revert column renames
    rename table(:projects), :tag_definition_id, to: :tag_id
    rename table(:entity_tags), :tag_definition_id, to: :tag_id

    # Rename tables back
    rename table(:entity_tags), to: table(:tagged_items)
    rename table(:tag_definitions), to: table(:tags)

    # Recreate trigger on old table
    execute """
    CREATE TRIGGER tag_consistency_trigger
      BEFORE INSERT ON tagged_items
      FOR EACH ROW
      EXECUTE FUNCTION check_tag_consistency();
    """

    # Revert functions to refer to tagged_items again
    execute """
    CREATE OR REPLACE FUNCTION check_cost_linking_consistency() RETURNS TRIGGER AS $$
    BEGIN
      -- Check if transaction has tags
      IF EXISTS (
        SELECT 1 FROM tagged_items ti 
        WHERE ti.entity_id = NEW.transaction_id 
          AND ti.entity_type = 'transaction'
      ) THEN
        RAISE EXCEPTION 'Cannot link a transaction that has tags';
      END IF;

      -- Check if cost invoice has tags
      IF EXISTS (
        SELECT 1 FROM tagged_items ti 
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
    CREATE OR REPLACE FUNCTION check_sales_linking_consistency() RETURNS TRIGGER AS $$
    BEGIN
      -- Check if transaction has tags
      IF EXISTS (
        SELECT 1 FROM tagged_items ti 
        WHERE ti.entity_id = NEW.transaction_id 
          AND ti.entity_type = 'transaction'
      ) THEN
        RAISE EXCEPTION 'Cannot link a transaction that has tags';
      END IF;

      -- Check if sales invoice has tags
      IF EXISTS (
        SELECT 1 FROM tagged_items ti 
        WHERE ti.entity_id = NEW.sales_invoice_id 
          AND ti.entity_type = 'sales_invoice'
      ) THEN
        RAISE EXCEPTION 'Cannot link a sales invoice that has tags';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end
