defmodule Firmowid.Repo.Migrations.RecalculateKsefSettlementAmounts do
  @moduledoc """
  Enqueues a one-off job that corrects KSeF cost invoice amounts which left out charges such as
  a bottle deposit. The invoice XML lives in S3, so the job reads it, not the migration. A
  database without KSeF invoices (tests, a fresh development setup) gets no job.
  """

  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO oban.oban_jobs (queue, worker, args, max_attempts)
    SELECT 'cost_invoices', 'Firmowid.Ksef.Workers.RecalculateSettlementAmountsWorker', '{}', 3
    WHERE EXISTS (SELECT 1 FROM cost_invoices WHERE ksef_number IS NOT NULL AND blob_id IS NOT NULL)
    """)
  end

  def down, do: :ok
end
