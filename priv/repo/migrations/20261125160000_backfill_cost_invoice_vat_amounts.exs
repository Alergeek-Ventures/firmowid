defmodule Firmowid.Repo.Migrations.BackfillCostInvoiceVatAmounts do
  @moduledoc """
  Enqueues a one-off job that fills the Polish VAT of KSeF cost invoices imported before the
  `vat_amount` column existed. Ash cannot express this backfill: the value comes from the invoice
  XML in S3, so the job reads it, not the migration. A database without KSeF invoices (tests, a
  fresh development setup) gets no job.
  """

  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO oban.oban_jobs (queue, worker, args, max_attempts)
    SELECT 'cost_invoices', 'Firmowid.Ksef.Workers.BackfillCostInvoiceVatWorker', '{}', 3
    WHERE EXISTS (
      SELECT 1 FROM cost_invoices
      WHERE ksef_number IS NOT NULL AND blob_id IS NOT NULL AND vat_amount IS NULL
    )
    """)
  end

  def down, do: :ok
end
