defmodule Firmowid.Repo.Migrations.RenameContractorsToCounterparties do
  use Ecto.Migration

  def up do
    # Drop BM25 index first (cannot be renamed, must be recreated)
    execute("DROP INDEX IF EXISTS contractors_search_idx;")

    # Rename table
    rename table(:contractors), to: table(:counterparties)

    # Rename column in sales_invoices
    rename table(:sales_invoices), :contractor_id, to: :counterparty_id

    # Rename indexes on counterparties table
    execute("ALTER INDEX contractors_pkey RENAME TO counterparties_pkey;")

    execute(
      "ALTER INDEX contractors_organization_id_index RENAME TO counterparties_organization_id_index;"
    )

    execute("ALTER INDEX contractors_type_index RENAME TO counterparties_type_index;")
    execute("ALTER INDEX contractors_tax_id_index RENAME TO counterparties_tax_id_index;")

    # Rename index on sales_invoices
    execute(
      "ALTER INDEX sales_invoices_contractor_id_index RENAME TO sales_invoices_counterparty_id_index;"
    )

    # Rename foreign key constraints
    execute(
      "ALTER TABLE counterparties RENAME CONSTRAINT contractors_organization_id_fkey TO counterparties_organization_id_fkey;"
    )

    execute(
      "ALTER TABLE sales_invoices RENAME CONSTRAINT sales_invoices_contractor_id_fkey TO sales_invoices_counterparty_id_fkey;"
    )

    # Recreate BM25 index with new name
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
  end

  def down do
    # Drop BM25 index first
    execute("DROP INDEX IF EXISTS counterparties_search_idx;")

    # Rename table back
    rename table(:counterparties), to: table(:contractors)

    # Rename column back in sales_invoices
    rename table(:sales_invoices), :counterparty_id, to: :contractor_id

    # Rename indexes back on contractors table
    execute("ALTER INDEX counterparties_pkey RENAME TO contractors_pkey;")

    execute(
      "ALTER INDEX counterparties_organization_id_index RENAME TO contractors_organization_id_index;"
    )

    execute("ALTER INDEX counterparties_type_index RENAME TO contractors_type_index;")
    execute("ALTER INDEX counterparties_tax_id_index RENAME TO contractors_tax_id_index;")

    # Rename index back on sales_invoices
    execute(
      "ALTER INDEX sales_invoices_counterparty_id_index RENAME TO sales_invoices_contractor_id_index;"
    )

    # Rename foreign key constraints back
    execute(
      "ALTER TABLE contractors RENAME CONSTRAINT counterparties_organization_id_fkey TO contractors_organization_id_fkey;"
    )

    execute(
      "ALTER TABLE sales_invoices RENAME CONSTRAINT sales_invoices_counterparty_id_fkey TO sales_invoices_contractor_id_fkey;"
    )

    # Recreate BM25 index with old name
    execute("""
      CREATE INDEX contractors_search_idx
      ON public.contractors
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
  end
end
