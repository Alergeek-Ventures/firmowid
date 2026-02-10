defmodule Firmowid.Repo.Migrations.EnsureSalesInvoiceItemsIndexIsSet do
  use Ecto.Migration

  def up do
    # Backfill NULL indices with row numbers (0-based) per sales_invoice
    execute("""
    WITH numbered AS (
      SELECT
        id,
        ROW_NUMBER() OVER (
          PARTITION BY sales_invoice_id
          ORDER BY inserted_at ASC
        ) - 1 AS computed_index
      FROM sales_invoice_items
      WHERE index IS NULL
    )
    UPDATE sales_invoice_items
    SET index = numbered.computed_index
    FROM numbered
    WHERE sales_invoice_items.id = numbered.id
    """)

    alter table(:sales_invoice_items) do
      modify :index, :integer, null: false
    end

    create unique_index(:sales_invoice_items, [:sales_invoice_id, :index])
  end

  def down do
    drop unique_index(:sales_invoice_items, [:sales_invoice_id, :index])

    alter table(:sales_invoice_items) do
      modify :index, :integer, null: true
    end
  end
end
