defmodule Firmowid.Repo.Migrations.RenameKsefObanWorkers do
  @moduledoc """
  Updates Oban job worker strings to match new module paths after
  the Ash domain consolidation.

  - KSeF workers: renamed to new Ash.Ksef.Workers namespace
  - Invoicing workers: renamed to new Ash.Invoicing.Workers namespace
  - Deleted workers (BankData, Currencies): cancelled — replaced by AshOban triggers
  """
  use Ecto.Migration

  @worker_renames %{
    # KSeF workers
    "Firmowid.Ksef.SessionWorker" => "Firmowid.Ash.Ksef.Workers.SessionWorker",
    "Firmowid.Ksef.SubmissionWorker" => "Firmowid.Ash.Ksef.Workers.SubmissionWorker",
    "Firmowid.Ksef.FetchWorker" => "Firmowid.Ash.Ksef.Workers.FetchWorker",
    "Firmowid.Ksef.FetchDispatcher" => "Firmowid.Ash.Ksef.Workers.FetchDispatcher",
    # Invoicing workers
    "Firmowid.Invoicing.Worker" => "Firmowid.Ash.Invoicing.Workers.MatchingWorker",
    "Firmowid.CostInvoices.InboundEmailWorker" =>
      "Firmowid.Ash.Invoicing.Workers.InboundEmailWorker"
  }

  # Workers that were deleted and replaced by AshOban triggers on resources.
  # Any pending jobs for these must be cancelled — the old modules no longer exist.
  @deleted_workers [
    "Firmowid.BankData.Worker",
    "Firmowid.BankData.CleanupWorker",
    "Firmowid.Currencies.CleanupWorker"
  ]

  def up do
    if oban_table_exists?() do
      for {old_name, new_name} <- @worker_renames do
        execute """
        UPDATE oban.oban_jobs
        SET worker = '#{new_name}'
        WHERE worker = '#{old_name}'
        """
      end

      for worker <- @deleted_workers do
        execute """
        UPDATE oban.oban_jobs
        SET state = 'cancelled', cancelled_at = NOW()
        WHERE worker = '#{worker}'
          AND state NOT IN ('completed', 'cancelled', 'discarded')
        """
      end
    end
  end

  def down do
    if oban_table_exists?() do
      for {old_name, new_name} <- @worker_renames do
        execute """
        UPDATE oban.oban_jobs
        SET worker = '#{old_name}'
        WHERE worker = '#{new_name}'
        """
      end

      # Deleted workers cannot be restored — their jobs stay cancelled.
    end
  end

  defp oban_table_exists? do
    %{rows: [[exists]]} =
      repo().query!(
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'oban' AND table_name = 'oban_jobs')"
      )

    exists
  end
end
