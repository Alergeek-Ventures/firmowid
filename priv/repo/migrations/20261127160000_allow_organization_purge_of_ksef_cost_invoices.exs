defmodule Firmowid.Repo.Migrations.AllowOrganizationPurgeOfKsefCostInvoices do
  @moduledoc """
  Lets the organization deletion transaction remove KSeF-imported cost invoices.

  A single KSeF cost invoice stays undeletable. Deleting its organization sets
  `firmowid.organization_purge` for the transaction, which the trigger honours.

  Hand-written because `mix ash.codegen` cannot express trigger functions.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION prevent_ksef_cost_invoice_modification()
    RETURNS TRIGGER AS $$
    BEGIN
      IF OLD.ksef_number IS NOT NULL THEN
        IF TG_OP = 'DELETE' AND current_setting('firmowid.organization_purge', true) IS DISTINCT FROM 'on' THEN
          RAISE EXCEPTION 'Cannot delete a KSeF-imported cost invoice';
        END IF;
      END IF;

      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end

  def down do
    execute("""
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
    """)
  end
end
