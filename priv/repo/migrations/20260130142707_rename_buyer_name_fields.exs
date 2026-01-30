defmodule Firmowid.Repo.Migrations.RenameBuyerNameFields do
  @moduledoc """
  Renames buyer name fields for clarity and adds constraints for data consistency.

  ## Schema Changes

  ### sales_invoices
  - `buyer_display_name` -> `buyer_full_name` (legal name for companies)
  - `buyer_name` -> `buyer_given_name` (first name for individuals)
  - `buyer_surname` stays the same
  - Adds new `buyer_display_name` (optional short/friendly name for both types)

  ### counterparties
  - `display_name` -> `full_name`
  - `name` -> `given_name`
  - `surname` stays the same
  - Adds new `display_name` (optional short/friendly name)

  ## Data Model

  | Type       | full_name        | given_name | surname | display_name     |
  |------------|------------------|------------|---------|------------------|
  | Company    | Required (legal) | NULL       | NULL    | Optional (short) |
  | Individual | NULL             | Required   | Required| Optional         |

  ## Constraints

  - Companies: must have full_name, must NOT have given_name/surname
  - Individuals: must have given_name + surname, must NOT have full_name
  """
  use Ecto.Migration

  def up do
    # ============================================
    # SALES_INVOICES
    # ============================================

    # Temporarily disable the trigger that prevents locked invoice modifications
    # (we need to clean up JDG records which may include locked invoices)
    execute("ALTER TABLE sales_invoices DISABLE TRIGGER locked_sales_invoice_trigger;")

    # Step 1: Clean up JDG records (companies with individual fields)
    execute("""
    UPDATE sales_invoices
    SET buyer_name = NULL, buyer_surname = NULL
    WHERE buyer_type = 'company'
      AND (COALESCE(buyer_name, '') != '' OR COALESCE(buyer_surname, '') != '');
    """)

    # Re-enable the trigger
    execute("ALTER TABLE sales_invoices ENABLE TRIGGER locked_sales_invoice_trigger;")

    # Step 2: Rename columns
    rename table(:sales_invoices), :buyer_display_name, to: :buyer_full_name
    rename table(:sales_invoices), :buyer_name, to: :buyer_given_name

    # Step 3: Add new display_name column
    alter table(:sales_invoices) do
      add :buyer_display_name, :string
    end

    # Step 4: Add check constraint for data consistency
    execute("""
    ALTER TABLE sales_invoices
    ADD CONSTRAINT sales_invoices_buyer_fields_by_type CHECK (
      CASE buyer_type
        WHEN 'company' THEN
          -- Companies: must have full_name, must NOT have given_name/surname
          COALESCE(buyer_full_name, '') != ''
          AND COALESCE(buyer_given_name, '') = ''
          AND COALESCE(buyer_surname, '') = ''
        WHEN 'individual' THEN
          -- Individuals: must have given_name + surname, must NOT have full_name
          COALESCE(buyer_full_name, '') = ''
          AND COALESCE(buyer_given_name, '') != ''
          AND COALESCE(buyer_surname, '') != ''
        ELSE
          -- Unknown type: no constraint (should not happen)
          TRUE
      END
      -- Only enforce when buyer is confirmed
      OR is_buyer_confirmed = FALSE
    );
    """)

    # Step 5: Recreate BM25 index with new column names in text_fields config
    execute("DROP INDEX IF EXISTS sales_invoices_search_idx;")

    execute("""
    CREATE INDEX sales_invoices_search_idx
    ON public.sales_invoices
    USING bm25 (
      id,
      buyer_full_name,
      buyer_given_name,
      buyer_surname,
      buyer_email,
      buyer_description,
      item_names,
      invoice_number,
      buyer_id
    )
    WITH (
      key_field = 'id',
      text_fields = '{
        "buyer_full_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "buyer_given_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "buyer_surname": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "buyer_email": {"tokenizer": {"type": "default"}},
        "buyer_description": {"tokenizer": {"type": "default"}},
        "item_names": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "invoice_number": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 6, "prefix_only": true}},
        "buyer_id": {"tokenizer": {"type": "keyword"}}
      }'
    );
    """)

    # ============================================
    # COUNTERPARTIES
    # ============================================

    # Step 1: Clean up company counterparties that have name/surname (should only have display_name)
    execute("""
    UPDATE counterparties
    SET name = NULL, surname = NULL
    WHERE type = 'company'
      AND (COALESCE(name, '') != '' OR COALESCE(surname, '') != '');
    """)

    # Step 2: Drop BM25 index (uses old column names)
    execute("DROP INDEX IF EXISTS counterparties_search_idx;")

    # Step 3: Rename columns
    rename table(:counterparties), :display_name, to: :full_name
    rename table(:counterparties), :name, to: :given_name

    # Step 4: Add new display_name column
    alter table(:counterparties) do
      add :display_name, :string
    end

    # Step 5: Add check constraint for data consistency
    execute("""
    ALTER TABLE counterparties
    ADD CONSTRAINT counterparties_fields_by_type CHECK (
      CASE type
        WHEN 'company' THEN
          -- Companies: must have full_name, must NOT have given_name/surname
          COALESCE(full_name, '') != ''
          AND COALESCE(given_name, '') = ''
          AND COALESCE(surname, '') = ''
        WHEN 'individual' THEN
          -- Individuals: must have given_name + surname, must NOT have full_name
          COALESCE(full_name, '') = ''
          AND COALESCE(given_name, '') != ''
          AND COALESCE(surname, '') != ''
        ELSE
          TRUE
      END
    );
    """)

    # Step 6: Recreate BM25 index with new column names
    execute("""
    CREATE INDEX counterparties_search_idx
    ON public.counterparties
    USING bm25 (
      id,
      full_name,
      given_name,
      surname,
      tax_id,
      email,
      display_name
    )
    WITH (
      key_field = 'id',
      text_fields = '{
        "full_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "given_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "surname": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "tax_id": {"tokenizer": {"type": "keyword"}},
        "email": {"tokenizer": {"type": "default"}},
        "display_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}}
      }'
    );
    """)
  end

  def down do
    # ============================================
    # COUNTERPARTIES (reverse order)
    # ============================================

    # Drop BM25 index
    execute("DROP INDEX IF EXISTS counterparties_search_idx;")

    # Drop constraint
    execute("ALTER TABLE counterparties DROP CONSTRAINT IF EXISTS counterparties_fields_by_type;")

    # Remove new column
    alter table(:counterparties) do
      remove :display_name
    end

    # Rename columns back
    rename table(:counterparties), :full_name, to: :display_name
    rename table(:counterparties), :given_name, to: :name

    # Recreate BM25 index with old column names
    execute("""
    CREATE INDEX counterparties_search_idx
    ON public.counterparties
    USING bm25 (
      id,
      display_name,
      name,
      surname,
      tax_id,
      email
    )
    WITH (
      key_field = 'id',
      text_fields = '{
        "display_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "surname": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 4, "prefix_only": false}},
        "tax_id": {"tokenizer": {"type": "keyword"}},
        "email": {"tokenizer": {"type": "default"}}
      }'
    );
    """)

    # ============================================
    # SALES_INVOICES (reverse order)
    # ============================================

    # Drop BM25 index
    execute("DROP INDEX IF EXISTS sales_invoices_search_idx;")

    # Drop constraint
    execute(
      "ALTER TABLE sales_invoices DROP CONSTRAINT IF EXISTS sales_invoices_buyer_fields_by_type;"
    )

    # Remove new column
    alter table(:sales_invoices) do
      remove :buyer_display_name
    end

    # Rename columns back
    rename table(:sales_invoices), :buyer_full_name, to: :buyer_display_name
    rename table(:sales_invoices), :buyer_given_name, to: :buyer_name

    # Recreate BM25 index with old column names
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
      buyer_id
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
        "buyer_id": {"tokenizer": {"type": "keyword"}}
      }'
    );
    """)

    # Note: JDG data cleanup cannot be reversed (data was NULLed)
  end
end
