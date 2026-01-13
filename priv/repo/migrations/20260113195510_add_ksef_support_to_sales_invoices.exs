defmodule Firmowid.Repo.Migrations.AddKsefSupportToSalesInvoices do
  @moduledoc """
  Squashed migration adding KSeF (Krajowy System e-Faktur) support.

  This migration consolidates:
  - Renaming organizations.identification_number -> nip
  - Adding KSeF columns to sales_invoices (ksef_number, locked_at, etc.)
  - Renaming buyer_nip -> buyer_id for FA(3) Podmiot2 compatibility
  - Converting buyer_country to ISO 2-letter codes
  - Creating locked invoice trigger and BM25 search index
  """
  use Ecto.Migration

  def up do
    # ============================================================================
    # SCHEMA CHANGES
    # ============================================================================

    # Rename organization identification_number to nip
    rename table(:organizations), :identification_number, to: :nip

    # Add KSeF columns to sales_invoices
    alter table(:sales_invoices) do
      # KSeF submission tracking
      add :ksef_number, :string
      add :ksef_session_reference_number, :string

      # Immutability enforcement
      add :locked_at, :utc_datetime

      # Invoice type for KSeF (VAT = regular, KOR = correction)
      add :ksef_invoice_kind, :string, default: "vat"

      # Self-referencing FK for correction invoices
      add :corrected_invoice_id,
          references(:sales_invoices, type: :binary_id, on_delete: :restrict)
    end

    # Rename buyer_nip to buyer_id (unified ID approach for KSeF FA(3) Podmiot2)
    # buyer_id_type is now derived at runtime from buyer_country and buyer_pesel
    rename table(:sales_invoices), :buyer_nip, to: :buyer_id

    # ============================================================================
    # DATA MIGRATIONS
    # ============================================================================

    # Pad organization NIP to 10 digits
    execute """
    UPDATE organizations
    SET nip = LPAD(nip, 10, '0')
    WHERE LENGTH(nip) < 10;
    """

    # Remove "PL" prefix from sales invoices seller NIP
    execute """
    UPDATE sales_invoices
    SET seller_nip = SUBSTRING(seller_nip FROM 3)
    WHERE seller_nip LIKE 'PL%'
    """

    # Convert buyer_country from full names to ISO 2-letter codes
    execute """
    UPDATE sales_invoices
    SET buyer_country =
      CASE
        WHEN LOWER(buyer_country) IN ('sweden', 'se') THEN 'SE'
        WHEN LOWER(buyer_country) IN ('usa', 'united states', 'united states of america', 'us') THEN 'US'
        WHEN LOWER(buyer_country) IN ('poland', 'polska', 'pl') THEN 'PL'
        WHEN LOWER(buyer_country) IN ('belgia', 'belgium', 'be') THEN 'BE'
        WHEN buyer_country IS NULL THEN 'PL'
        ELSE 'PL'
      END
    WHERE buyer_country IS NULL OR CHAR_LENGTH(buyer_country) != 2 OR buyer_country !~ '^[A-Z]{2}$'
    """

    # ============================================================================
    # INDEXES
    # ============================================================================

    # Unique index for KSeF number (only when not null)
    create unique_index(:sales_invoices, [:ksef_number],
             name: :sales_invoices_ksef_number_idx,
             where: "ksef_number IS NOT NULL"
           )

    # Index for finding locked invoices
    create index(:sales_invoices, [:locked_at],
             name: :sales_invoices_locked_at_idx,
             where: "locked_at IS NOT NULL"
           )

    create index(:sales_invoices, [:corrected_invoice_id])

    # Recreate BM25 index with buyer_id column name
    execute "DROP INDEX IF EXISTS sales_invoices_search_idx;"

    execute """
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
    """

    # ============================================================================
    # CONSTRAINTS
    # ============================================================================

    # Database trigger to prevent modification of locked sales invoices
    execute """
    CREATE OR REPLACE FUNCTION prevent_locked_sales_invoice_modification()
    RETURNS TRIGGER AS $$
    BEGIN
      -- Block DELETE on locked invoices
      IF TG_OP = 'DELETE' THEN
        IF OLD.locked_at IS NOT NULL THEN
          RAISE EXCEPTION 'Cannot delete a locked sales invoice (locked_at is set)';
        END IF;
        RETURN OLD;
      END IF;

      -- Block UPDATE on locked invoices if any protected field is modified
      -- Allowed fields: ksef_number, ksef_session_reference_number, locked_at, updated_at
      IF TG_OP = 'UPDATE' AND OLD.locked_at IS NOT NULL THEN
        IF ROW(
          OLD.id, OLD.invoice_type, OLD.invoice_number, OLD.sale_date, OLD.issue_date,
          OLD.due_date, OLD.payment_method, OLD.currency, OLD.is_basic_info_confirmed,
          OLD.seller_nip, OLD.seller_display_name, OLD.seller_address, OLD.seller_name,
          OLD.seller_surname, OLD.seller_account_number, OLD.is_seller_confirmed,
          OLD.buyer_type, OLD.buyer_id, OLD.buyer_display_name, OLD.buyer_name,
          OLD.buyer_surname, OLD.buyer_pesel, OLD.buyer_address, OLD.buyer_country,
          OLD.buyer_is_different_mail_address, OLD.buyer_mail_address, OLD.buyer_mail_country,
          OLD.buyer_email, OLD.buyer_phone, OLD.buyer_description, OLD.is_buyer_confirmed,
          OLD.are_sales_invoice_items_confirmed, OLD.is_cash_account, OLD.is_reverse_charge,
          OLD.skip_invoicing, OLD.item_names, OLD.ksef_invoice_kind,
          OLD.corrected_invoice_id, OLD.organization_id, OLD.inserted_at
        ) IS DISTINCT FROM ROW(
          NEW.id, NEW.invoice_type, NEW.invoice_number, NEW.sale_date, NEW.issue_date,
          NEW.due_date, NEW.payment_method, NEW.currency, NEW.is_basic_info_confirmed,
          NEW.seller_nip, NEW.seller_display_name, NEW.seller_address, NEW.seller_name,
          NEW.seller_surname, NEW.seller_account_number, NEW.is_seller_confirmed,
          NEW.buyer_type, NEW.buyer_id, NEW.buyer_display_name, NEW.buyer_name,
          NEW.buyer_surname, NEW.buyer_pesel, NEW.buyer_address, NEW.buyer_country,
          NEW.buyer_is_different_mail_address, NEW.buyer_mail_address, NEW.buyer_mail_country,
          NEW.buyer_email, NEW.buyer_phone, NEW.buyer_description, NEW.is_buyer_confirmed,
          NEW.are_sales_invoice_items_confirmed, NEW.is_cash_account, NEW.is_reverse_charge,
          NEW.skip_invoicing, NEW.item_names, NEW.ksef_invoice_kind,
          NEW.corrected_invoice_id, NEW.organization_id, NEW.inserted_at
        ) THEN
          RAISE EXCEPTION 'Cannot modify a locked sales invoice. Only ksef_number, ksef_session_reference_number, and locked_at may be updated.';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER locked_sales_invoice_trigger
    BEFORE UPDATE OR DELETE ON sales_invoices
    FOR EACH ROW EXECUTE FUNCTION prevent_locked_sales_invoice_modification();
    """
  end

  def down do
    # ============================================================================
    # DROP CONSTRAINTS
    # ============================================================================

    execute "DROP TRIGGER IF EXISTS locked_sales_invoice_trigger ON sales_invoices;"
    execute "DROP FUNCTION IF EXISTS prevent_locked_sales_invoice_modification();"

    # ============================================================================
    # DROP BM25 INDEX AND RECREATE WITH buyer_nip
    # ============================================================================

    execute "DROP INDEX IF EXISTS sales_invoices_search_idx;"

    # ============================================================================
    # DROP INDEXES
    # ============================================================================

    drop index(:sales_invoices, [:corrected_invoice_id])
    drop index(:sales_invoices, [:locked_at], name: :sales_invoices_locked_at_idx)
    drop index(:sales_invoices, [:ksef_number], name: :sales_invoices_ksef_number_idx)

    # ============================================================================
    # REVERSE DATA MIGRATIONS (LOSSY)
    # ============================================================================

    # NOTE: These are best-effort reversals. The original values cannot be fully restored.

    # Convert buyer_country from ISO codes back to full names (lossy - unknown originals default to 'Poland')
    execute """
    UPDATE sales_invoices
    SET buyer_country =
      CASE
        WHEN buyer_country = 'SE' THEN 'Sweden'
        WHEN buyer_country = 'US' THEN 'USA'
        WHEN buyer_country = 'PL' THEN 'Poland'
        WHEN buyer_country = 'BE' THEN 'Belgium'
        ELSE buyer_country
      END
    WHERE CHAR_LENGTH(buyer_country) = 2 AND buyer_country ~ '^[A-Z]{2}$'
    """

    # NOTE: Cannot reverse seller_nip PL prefix removal or organization NIP padding

    # ============================================================================
    # REVERSE SCHEMA CHANGES
    # ============================================================================

    # Rename buyer_id back to buyer_nip
    rename table(:sales_invoices), :buyer_id, to: :buyer_nip

    # Drop KSeF columns from sales_invoices
    alter table(:sales_invoices) do
      remove :corrected_invoice_id
      remove :ksef_invoice_kind
      remove :locked_at
      remove :ksef_session_reference_number
      remove :ksef_number
    end

    # Rename organization nip back to identification_number
    rename table(:organizations), :nip, to: :identification_number

    # Recreate original BM25 index with buyer_nip
    execute """
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
    """
  end
end
