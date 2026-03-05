defmodule Firmowid.Repo.Migrations.AllowKsefCostInvoiceUpdates do
  use Ecto.Migration

  @moduledoc "Allows updates on KSeF cost invoices while preventing deletions."

  def up do
    execute "DROP TRIGGER IF EXISTS ksef_cost_invoice_trigger ON cost_invoices;"
    execute "DROP FUNCTION IF EXISTS prevent_ksef_cost_invoice_modification();"

    execute """
    CREATE OR REPLACE FUNCTION prevent_ksef_cost_invoice_modification()
    RETURNS TRIGGER AS $$
    BEGIN
      IF OLD.ksef_number IS NOT NULL THEN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'Cannot delete a KSeF-imported cost invoice';
        END IF;
      END IF;

      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER ksef_cost_invoice_trigger
    BEFORE DELETE ON cost_invoices
    FOR EACH ROW EXECUTE FUNCTION prevent_ksef_cost_invoice_modification();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS ksef_cost_invoice_trigger ON cost_invoices;"
    execute "DROP FUNCTION IF EXISTS prevent_ksef_cost_invoice_modification();"

    execute """
    CREATE OR REPLACE FUNCTION prevent_ksef_cost_invoice_modification()
    RETURNS TRIGGER AS $$
    BEGIN
      IF OLD.ksef_number IS NOT NULL OR OLD.ksef_downloaded_at IS NOT NULL OR OLD.ksef_permanent_storage_date IS NOT NULL THEN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'Cannot delete a KSeF-imported cost invoice';
        END IF;

        IF TG_OP = 'UPDATE' THEN
          IF ROW(
            OLD.seller,
            OLD.seller_address,
            OLD.seller_display_name,
            OLD.account_number,
            OLD.sale_date,
            OLD.issue_date,
            OLD.due_date,
            OLD.total_amount,
            OLD.currency,
            OLD.description,
            OLD.invoice_identifier,
            OLD.ksef_number,
            OLD.ksef_permanent_storage_date,
            OLD.ksef_downloaded_at,
            OLD.seller_nip,
            OLD.seller_country_code,
            OLD.seller_email,
            OLD.seller_phone,
            OLD.invoice_type,
            OLD.original_invoice_number,
            OLD.payment_method
          ) IS DISTINCT FROM ROW(
            NEW.seller,
            NEW.seller_address,
            NEW.seller_display_name,
            NEW.account_number,
            NEW.sale_date,
            NEW.issue_date,
            NEW.due_date,
            NEW.total_amount,
            NEW.currency,
            NEW.description,
            NEW.invoice_identifier,
            NEW.ksef_number,
            NEW.ksef_permanent_storage_date,
            NEW.ksef_downloaded_at,
            NEW.seller_nip,
            NEW.seller_country_code,
            NEW.seller_email,
            NEW.seller_phone,
            NEW.invoice_type,
            NEW.original_invoice_number,
            NEW.payment_method
          ) THEN
            RAISE EXCEPTION 'Cannot modify KSeF-imported invoice data. Only skip_invoicing may be updated.';
          END IF;
        END IF;
      END IF;

      IF TG_OP = 'DELETE' THEN
        RETURN OLD;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER ksef_cost_invoice_trigger
    BEFORE UPDATE OR DELETE ON cost_invoices
    FOR EACH ROW EXECUTE FUNCTION prevent_ksef_cost_invoice_modification();
    """
  end
end
