defmodule Firmowid.Repo.Migrations.ChangeVatRateToString do
  @moduledoc """
  Converts vat_rate from decimal to string to match KSeF FA(3) TStawkaPodatku codes.

  Migration logic:
  - vat_rate = 0 with is_reverse_charge = true → "oo"
  - vat_rate = 0 with is_reverse_charge = false → "0 KR"
  - vat_rate = 23, 8, 5, etc. → "23", "8", "5", etc.
  """
  use Ecto.Migration

  @valid_rates [
    "'23'",
    "'22'",
    "'8'",
    "'7'",
    "'5'",
    "'4'",
    "'3'",
    "'0 KR'",
    "'0 WDT'",
    "'0 EX'",
    "'zw'",
    "'oo'",
    "'np I'",
    "'np II'"
  ]

  def up do
    # 1. Add new string column
    alter table(:sales_invoice_items) do
      add :vat_rate_new, :string
    end

    flush()

    # 2. Migrate data based on is_reverse_charge flag from parent invoice
    # Note: Invalid rates (not in 0, 3, 4, 5, 7, 8, 22, 23) are defaulted to '23'
    execute """
    UPDATE sales_invoice_items
    SET vat_rate_new = CASE
      WHEN vat_rate = 0 AND EXISTS (
        SELECT 1 FROM sales_invoices
        WHERE sales_invoices.id = sales_invoice_items.sales_invoice_id
        AND sales_invoices.is_reverse_charge = true
      ) THEN 'oo'
      WHEN vat_rate = 0 THEN '0 KR'
      WHEN vat_rate IN (3, 4, 5, 7, 8, 22, 23) THEN vat_rate::integer::text
      ELSE '23'
    END
    """

    # 3. Drop old column and rename new
    alter table(:sales_invoice_items) do
      remove :vat_rate
    end

    rename table(:sales_invoice_items), :vat_rate_new, to: :vat_rate

    # 4. Add CHECK constraint for valid KSeF rates
    create constraint(:sales_invoice_items, :valid_vat_rate,
             check: "vat_rate IN (#{Enum.join(@valid_rates, ", ")})"
           )
  end

  def down do
    # Drop constraint
    drop constraint(:sales_invoice_items, :valid_vat_rate)

    # Add decimal column back
    alter table(:sales_invoice_items) do
      add :vat_rate_old, :decimal
    end

    flush()

    # Convert back to decimal
    execute """
    UPDATE sales_invoice_items
    SET vat_rate_old = CASE
      WHEN vat_rate IN ('0 KR', '0 WDT', '0 EX', 'zw', 'oo', 'np I', 'np II') THEN 0
      ELSE vat_rate::integer
    END
    """

    # Drop string column and rename decimal back
    alter table(:sales_invoice_items) do
      remove :vat_rate
    end

    rename table(:sales_invoice_items), :vat_rate_old, to: :vat_rate
  end
end
