defmodule Firmowid.Repo.Migrations.EnforceNonPositiveTotalAmountForNonCorrectionCostInvoices do
  use Ecto.Migration

  @constraint_name :cost_invoices_non_correction_total_amount_non_positive

  def up do
    execute("""
    UPDATE cost_invoices
    SET total_amount = -total_amount
    WHERE ksef_number IS NOT NULL
    """)

    create constraint(:cost_invoices, @constraint_name,
             check:
               "(COALESCE(invoice_type IN ('kor', 'kor_zal', 'kor_roz'), FALSE)) OR total_amount <= 0"
           )
  end

  def down do
    drop constraint(:cost_invoices, @constraint_name)
  end
end
