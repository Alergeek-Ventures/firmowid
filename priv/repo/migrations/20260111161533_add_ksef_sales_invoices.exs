defmodule Firmowid.Repo.Migrations.AddKsefSalesInvoices do
  use Ecto.Migration

  def up do
    # Sales invoices modifications for KSeF support
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

      # NOTE: We use a unified buyer ID approach instead of separate fields:
      # - buyer_nip is renamed to buyer_id in migration 20260112202742
      # - buyer_id_type is derived at runtime from buyer_country and buyer_pesel
      # - buyer_country is used directly for KodUE/KodKraju in KSeF XML
    end

    # ============================================================================
    # DATA MIGRATIONS
    # ============================================================================

    # Pad organization identification numbers to 10 digits
    execute """
    UPDATE organizations
    SET identification_number = LPAD(identification_number, 10, '0')
    WHERE LENGTH(identification_number) < 10;
    """

    # Remove "PL" prefix from sales invoices seller NIP
    execute """
    UPDATE sales_invoices
    SET seller_nip = SUBSTRING(seller_nip FROM 3)
    WHERE seller_nip LIKE 'PL%'
    """

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

    # ============================================================================
    # CONSTRAINTS
    # ============================================================================

    # Database trigger to prevent modification of locked sales invoices
    # NOTE: Uses buyer_nip here; migration 20260112202742 updates this to buyer_id
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
  end

  def down do
    # Drop trigger and function
    execute "DROP TRIGGER IF EXISTS locked_sales_invoice_trigger ON sales_invoices;"
    execute "DROP FUNCTION IF EXISTS prevent_locked_sales_invoice_modification();"

    # Drop indexes
    drop index(:sales_invoices, [:corrected_invoice_id])
    drop index(:sales_invoices, [:locked_at], name: :sales_invoices_locked_at_idx)
    drop index(:sales_invoices, [:ksef_number], name: :sales_invoices_ksef_number_idx)

    # Reverse data migrations - not possible, so we skip them

    # Drop columns from sales_invoices
    alter table(:sales_invoices) do
      remove :corrected_invoice_id
      remove :ksef_invoice_kind
      remove :locked_at
      remove :ksef_session_reference_number
      remove :ksef_number
    end
  end
end
