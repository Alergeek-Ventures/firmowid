defmodule Firmowid.Repo.Migrations.AddKsefInvoiceChecksumToSalesInvoices do
  @moduledoc """
  Adds KSeF invoice checksum storage for sales invoices.
  """

  use Ecto.Migration

  def up do
    alter table(:sales_invoices) do
      add :ksef_invoice_checksum, :string
    end

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
      -- Allowed fields: ksef_number, ksef_session_reference_number, ksef_invoice_checksum, locked_at, skip_invoicing, updated_at
      IF TG_OP = 'UPDATE' AND OLD.locked_at IS NOT NULL THEN
        IF ROW(
          OLD.id, OLD.invoice_type, OLD.invoice_number, OLD.sale_date, OLD.issue_date,
          OLD.due_date, OLD.payment_method, OLD.currency,
          OLD.seller_nip, OLD.seller_display_name, OLD.seller_address, OLD.seller_name,
          OLD.seller_surname, OLD.seller_account_number,
          OLD.buyer_type, OLD.buyer_id, OLD.buyer_display_name, OLD.buyer_full_name,
          OLD.buyer_given_name, OLD.buyer_surname, OLD.buyer_pesel, OLD.buyer_address,
          OLD.buyer_country, OLD.buyer_is_different_mail_address, OLD.buyer_mail_address,
          OLD.buyer_mail_country, OLD.buyer_email, OLD.buyer_phone, OLD.buyer_description,
          OLD.is_cash_account, OLD.is_reverse_charge, OLD.item_names,
          OLD.ksef_invoice_kind, OLD.corrected_invoice_id, OLD.counterparty_id,
          OLD.organization_id, OLD.inserted_at
        ) IS DISTINCT FROM ROW(
          NEW.id, NEW.invoice_type, NEW.invoice_number, NEW.sale_date, NEW.issue_date,
          NEW.due_date, NEW.payment_method, NEW.currency,
          NEW.seller_nip, NEW.seller_display_name, NEW.seller_address, NEW.seller_name,
          NEW.seller_surname, NEW.seller_account_number,
          NEW.buyer_type, NEW.buyer_id, NEW.buyer_display_name, NEW.buyer_full_name,
          NEW.buyer_given_name, NEW.buyer_surname, NEW.buyer_pesel, NEW.buyer_address,
          NEW.buyer_country, NEW.buyer_is_different_mail_address, NEW.buyer_mail_address,
          NEW.buyer_mail_country, NEW.buyer_email, NEW.buyer_phone, NEW.buyer_description,
          NEW.is_cash_account, NEW.is_reverse_charge, NEW.item_names,
          NEW.ksef_invoice_kind, NEW.corrected_invoice_id, NEW.counterparty_id,
          NEW.organization_id, NEW.inserted_at
        ) THEN
          RAISE EXCEPTION 'Cannot modify a locked sales invoice. Only ksef_number, ksef_session_reference_number, ksef_invoice_checksum, locked_at, and skip_invoicing may be updated.';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  def down do
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
      -- Allowed fields: ksef_number, ksef_session_reference_number, locked_at, skip_invoicing, updated_at
      IF TG_OP = 'UPDATE' AND OLD.locked_at IS NOT NULL THEN
        IF ROW(
          OLD.id, OLD.invoice_type, OLD.invoice_number, OLD.sale_date, OLD.issue_date,
          OLD.due_date, OLD.payment_method, OLD.currency,
          OLD.seller_nip, OLD.seller_display_name, OLD.seller_address, OLD.seller_name,
          OLD.seller_surname, OLD.seller_account_number,
          OLD.buyer_type, OLD.buyer_id, OLD.buyer_display_name, OLD.buyer_full_name,
          OLD.buyer_given_name, OLD.buyer_surname, OLD.buyer_pesel, OLD.buyer_address,
          OLD.buyer_country, OLD.buyer_is_different_mail_address, OLD.buyer_mail_address,
          OLD.buyer_mail_country, OLD.buyer_email, OLD.buyer_phone, OLD.buyer_description,
          OLD.is_cash_account, OLD.is_reverse_charge, OLD.item_names,
          OLD.ksef_invoice_kind, OLD.corrected_invoice_id, OLD.counterparty_id,
          OLD.organization_id, OLD.inserted_at
        ) IS DISTINCT FROM ROW(
          NEW.id, NEW.invoice_type, NEW.invoice_number, NEW.sale_date, NEW.issue_date,
          NEW.due_date, NEW.payment_method, NEW.currency,
          NEW.seller_nip, NEW.seller_display_name, NEW.seller_address, NEW.seller_name,
          NEW.seller_surname, NEW.seller_account_number,
          NEW.buyer_type, NEW.buyer_id, NEW.buyer_display_name, NEW.buyer_full_name,
          NEW.buyer_given_name, NEW.buyer_surname, NEW.buyer_pesel, NEW.buyer_address,
          NEW.buyer_country, NEW.buyer_is_different_mail_address, NEW.buyer_mail_address,
          NEW.buyer_mail_country, NEW.buyer_email, NEW.buyer_phone, NEW.buyer_description,
          NEW.is_cash_account, NEW.is_reverse_charge, NEW.item_names,
          NEW.ksef_invoice_kind, NEW.corrected_invoice_id, NEW.counterparty_id,
          NEW.organization_id, NEW.inserted_at
        ) THEN
          RAISE EXCEPTION 'Cannot modify a locked sales invoice. Only ksef_number, ksef_session_reference_number, locked_at, and skip_invoicing may be updated.';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    alter table(:sales_invoices) do
      remove :ksef_invoice_checksum
    end
  end
end
