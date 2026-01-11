defmodule Firmowid.Repo.Migrations.UnifyBuyerIdentification do
  @moduledoc """
  Renames buyer_nip to buyer_id for KSeF FA(3) Podmiot2 compatibility.

  The buyer_id_type is now derived at runtime from:
  - buyer_pesel (if present -> :no_id for individuals)
  - buyer_country (PL -> :nip, EU -> :eu_vat, other -> :other_id)

  This migration:
  1. Renames buyer_nip -> buyer_id
  2. Recreates BM25 index with new column name
  3. Updates the locked invoice trigger to use buyer_id
  """
  use Ecto.Migration

  def up do
    # Step 1: Rename buyer_nip -> buyer_id
    rename table(:sales_invoices), :buyer_nip, to: :buyer_id

    # Step 2: Recreate BM25 index with new column name
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

    # Step 3: Update the locked invoice trigger to use buyer_id instead of buyer_nip
    execute "DROP TRIGGER IF EXISTS locked_sales_invoice_trigger ON sales_invoices;"
    execute "DROP FUNCTION IF EXISTS prevent_locked_sales_invoice_modification();"

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
    # Restore trigger with buyer_nip
    execute "DROP TRIGGER IF EXISTS locked_sales_invoice_trigger ON sales_invoices;"
    execute "DROP FUNCTION IF EXISTS prevent_locked_sales_invoice_modification();"

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
          OLD.buyer_type, OLD.buyer_nip, OLD.buyer_display_name, OLD.buyer_name,
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
          NEW.buyer_type, NEW.buyer_nip, NEW.buyer_display_name, NEW.buyer_name,
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

    # Drop BM25 index
    execute "DROP INDEX IF EXISTS sales_invoices_search_idx;"

    # Rename back
    rename table(:sales_invoices), :buyer_id, to: :buyer_nip

    # Recreate original BM25 index
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
