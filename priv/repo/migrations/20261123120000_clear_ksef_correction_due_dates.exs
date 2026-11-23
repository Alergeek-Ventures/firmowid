defmodule Firmowid.Repo.Migrations.ClearKsefCorrectionDueDates do
  @moduledoc """
  Enqueues a one-off job that clears the due date the KSeF import made up for cost invoice
  corrections without a payment term. The invoice XML lives in S3, so the job reads it, not the
  migration. A database without such corrections (tests, a fresh development setup) gets no job.
  """

  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO oban.oban_jobs (queue, worker, args, max_attempts)
    SELECT 'cost_invoices', 'Firmowid.Ksef.Workers.ClearCorrectionDueDatesWorker', '{}', 3
    WHERE EXISTS (
      SELECT 1 FROM cost_invoices
      WHERE ksef_number IS NOT NULL
        AND original_invoice_ksef_number IS NOT NULL
        AND blob_id IS NOT NULL
        AND due_date IS NOT NULL
    )
    """)
  end

  def down, do: :ok
end
