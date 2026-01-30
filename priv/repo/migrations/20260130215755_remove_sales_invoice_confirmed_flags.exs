defmodule Firmowid.Repo.Migrations.RemoveSalesInvoiceConfirmedFlags do
  @moduledoc """
  Removes the 4 is_*_confirmed boolean flags from sales_invoices.

  These flags were used to track wizard step confirmations but are redundant:
  - Drafts (invoice_number IS NULL) always have all flags = false
  - Confirmed invoices (invoice_number IS NOT NULL) always have all flags = true

  The invoice state is now determined solely by invoice_number presence:
  - draft?/1 = invoice_number IS NULL
  - confirmed?/1 = invoice_number IS NOT NULL
  """
  use Ecto.Migration

  def up do
    # Fix any inconsistent data before removing columns
    # (2 confirmed invoices had some flags set to false)
    execute """
    UPDATE sales_invoices
    SET is_basic_info_confirmed = true,
        is_seller_confirmed = true,
        is_buyer_confirmed = true,
        are_sales_invoice_items_confirmed = true
    WHERE invoice_number IS NOT NULL
    """

    alter table(:sales_invoices) do
      remove :is_basic_info_confirmed
      remove :is_seller_confirmed
      remove :is_buyer_confirmed
      remove :are_sales_invoice_items_confirmed
    end
  end

  def down do
    alter table(:sales_invoices) do
      add :is_basic_info_confirmed, :boolean, default: false, null: false
      add :is_seller_confirmed, :boolean, default: false, null: false
      add :is_buyer_confirmed, :boolean, default: false, null: false
      add :are_sales_invoice_items_confirmed, :boolean, default: false, null: false
    end

    # Restore flags based on invoice_number presence
    execute """
    UPDATE sales_invoices
    SET is_basic_info_confirmed = (invoice_number IS NOT NULL),
        is_seller_confirmed = (invoice_number IS NOT NULL),
        is_buyer_confirmed = (invoice_number IS NOT NULL),
        are_sales_invoice_items_confirmed = (invoice_number IS NOT NULL)
    """
  end
end
