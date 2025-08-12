defmodule Firmowid.Repo.Migrations.AddTagsToCostInvoicesTransactionsAndConstraints do
  use Ecto.Migration

  def up do
    # Update tagged_items to support linking entity types
    # Drop the constraint if it exists, then recreate with new entity types
    execute "ALTER TABLE tagged_items DROP CONSTRAINT IF EXISTS tagged_items_entity_type_check"

    create constraint(:tagged_items, :tagged_items_entity_type_check,
             check:
               "entity_type IN ('transaction', 'sales_invoice', 'cost_invoice', 'cost_invoices_transactions', 'sales_invoices_transactions')"
           )

    # Create trigger function to enforce tag consistency
    execute """
    CREATE OR REPLACE FUNCTION check_tag_consistency() RETURNS TRIGGER AS $$
    BEGIN
      -- Check if trying to tag a linked transaction
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

      -- Check if trying to tag a linked cost invoice
      IF NEW.entity_type = 'cost_invoice' THEN
        IF EXISTS (
          SELECT 1 FROM cost_invoices_transactions cit 
          WHERE cit.cost_invoice_id = NEW.entity_id
        ) THEN
          RAISE EXCEPTION 'Cannot tag a cost invoice that is linked to a transaction';
        END IF;
      END IF;

      -- Check if trying to tag a linked sales invoice
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

    # Create separate trigger functions for cost and sales invoice linking
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

    # Create triggers
    execute "DROP TRIGGER IF EXISTS tag_consistency_trigger ON tagged_items"

    execute """
    CREATE TRIGGER tag_consistency_trigger
      BEFORE INSERT ON tagged_items
      FOR EACH ROW
      EXECUTE FUNCTION check_tag_consistency();
    """

    execute "DROP TRIGGER IF EXISTS cost_linking_consistency_trigger ON cost_invoices_transactions"

    execute """
    CREATE TRIGGER cost_linking_consistency_trigger
      BEFORE INSERT ON cost_invoices_transactions
      FOR EACH ROW
      EXECUTE FUNCTION check_cost_linking_consistency();
    """

    execute "DROP TRIGGER IF EXISTS sales_linking_consistency_trigger ON sales_invoices_transactions"

    execute """
    CREATE TRIGGER sales_linking_consistency_trigger
      BEFORE INSERT ON sales_invoices_transactions
      FOR EACH ROW
      EXECUTE FUNCTION check_sales_linking_consistency();
    """
  end

  def down do
    # Drop triggers first
    execute "DROP TRIGGER IF EXISTS tag_consistency_trigger ON tagged_items"

    execute "DROP TRIGGER IF EXISTS cost_linking_consistency_trigger ON cost_invoices_transactions"

    execute "DROP TRIGGER IF EXISTS sales_linking_consistency_trigger ON sales_invoices_transactions"

    # Drop trigger functions
    execute "DROP FUNCTION IF EXISTS check_tag_consistency() CASCADE"
    execute "DROP FUNCTION IF EXISTS check_cost_linking_consistency() CASCADE"
    execute "DROP FUNCTION IF EXISTS check_sales_linking_consistency() CASCADE"

    # Restore original constraint
    execute "ALTER TABLE tagged_items DROP CONSTRAINT IF EXISTS tagged_items_entity_type_check"

    create constraint(:tagged_items, :tagged_items_entity_type_check,
             check: "entity_type IN ('transaction', 'sales_invoice', 'cost_invoice')"
           )
  end
end
