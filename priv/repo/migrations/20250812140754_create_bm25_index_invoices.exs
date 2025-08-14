defmodule Firmowid.Repo.Migrations.CreateInvoiceBm25Index do
  use Ecto.Migration

  def up do
    # create extension - denormalise item names (no other good way to index them)
    execute("""
      ALTER TABLE sales_invoices
      ADD COLUMN IF NOT EXISTS item_names TEXT;
    """)

    execute("""
      CREATE OR REPLACE FUNCTION update_sales_invoice_item_names()
      RETURNS TRIGGER AS $$
      DECLARE
        sid UUID;
      BEGIN
        IF (TG_OP = 'DELETE') THEN
          sid := OLD.sales_invoice_id;
        ELSE
          sid := NEW.sales_invoice_id;
        END IF;

        UPDATE sales_invoices
        SET item_names = COALESCE((
          SELECT string_agg(name, ' ')
          FROM sales_invoice_items
          WHERE sales_invoice_id = sid
        ), '')
        WHERE id = sid;

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    """)

    # common safeguard for idempotency of 'up'
    execute("""
      DROP TRIGGER IF EXISTS sales_invoice_items_update_names ON sales_invoice_items;
    """)

    execute("""
      CREATE TRIGGER sales_invoice_items_update_names
      AFTER INSERT OR UPDATE OR DELETE ON sales_invoice_items
      FOR EACH ROW EXECUTE FUNCTION update_sales_invoice_item_names();
    """)

    execute("""
      UPDATE sales_invoices
      SET item_names = (
        SELECT string_agg(name, ' ')
        FROM sales_invoice_items
        WHERE sales_invoice_id = sales_invoices.id
      );
    """)

    # for idempotency
    execute("DROP INDEX IF EXISTS sales_invoices_search_idx;")
    # sales invoices
    execute("""
      CREATE INDEX sales_invoices_search_idx
      ON public.sales_invoices
      USING bm25 (
        id,
        buyer_display_name,
        buyer_name,
        buyer_surname,
        buyer_email,
        buyer_description,
        item_names,

        invoice_number,
        buyer_nip
      )
      WITH (
        key_field = 'id',
        text_fields = '{
        "buyer_display_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "buyer_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "buyer_surname": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "buyer_email": {"tokenizer": {"type": "default"}},
        "buyer_description": {"tokenizer": {"type": "default"}},
        "item_names": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "invoice_number": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 6, "prefix_only": true}},
        "buyer_nip": {"tokenizer": {"type": "keyword"}}
        }'
      );
    """)

    # for idempotency
    execute("DROP INDEX IF EXISTS cost_invoices_search_idx;")
    # cost invoices
    execute("""
      CREATE INDEX cost_invoices_search_idx
      ON public.cost_invoices
      USING bm25 (
        id,
        seller,
        seller_display_name,
        description,

        invoice_identifier
      )
      WITH (
        key_field = 'id',
        text_fields = '{
          "seller": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
          "seller_display_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
          "description": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
          "invoice_identifier": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 6, "prefix_only": true}}
        }'
      );
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS cost_invoices_search_idx;")
    execute("DROP INDEX IF EXISTS sales_invoices_search_idx;")
    execute("DROP TRIGGER IF EXISTS sales_invoice_items_update_names ON sales_invoice_items;")
    execute("DROP FUNCTION IF EXISTS update_sales_invoice_item_names();")
    execute("ALTER TABLE sales_invoices DROP COLUMN IF EXISTS item_names;")
  end
end
