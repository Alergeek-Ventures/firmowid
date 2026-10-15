defmodule Firmowid.Repo.Migrations.ReturnUnsentInvoicesToDrafts do
  @moduledoc """
  Returns numbered VAT invoices that never reached KSeF to unnumbered drafts.

  Issuance now always submits to KSeF, so a numbered invoice outside KSeF is only
  valid while its submission is in flight. Invoices locked for submission or with a
  queued submission job are left for the submission worker to finish.

  Data-only migration: Ash codegen generates schema changes, not data updates.
  """

  use Ecto.Migration

  def up do
    execute """
    UPDATE sales_invoices AS invoice
    SET invoice_number = NULL
    WHERE invoice.ksef_invoice_kind = 'vat'
      AND invoice.invoice_number IS NOT NULL
      AND invoice.ksef_number IS NULL
      AND invoice.locked_at IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM oban.oban_jobs AS job
        WHERE job.worker = 'Firmowid.Ash.Ksef.Workers.SubmissionWorker'
          AND job.args->>'sales_invoice_id' = invoice.id::text
          AND job.state IN ('available', 'scheduled', 'executing', 'retryable')
      )
    """
  end

  def down, do: :ok
end
