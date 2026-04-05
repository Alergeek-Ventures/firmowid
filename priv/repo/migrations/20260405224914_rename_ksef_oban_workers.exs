defmodule Firmowid.Repo.Migrations.RenameKsefObanWorkers do
  @moduledoc """
  Updates Oban job worker strings to match new module paths after
  the KSeF domain consolidation (Firmowid.Ksef → Firmowid.Ash.Ksef).
  """
  use Ecto.Migration

  @worker_renames %{
    "Firmowid.Ksef.SessionWorker" => "Firmowid.Ash.Ksef.Workers.SessionWorker",
    "Firmowid.Ksef.SubmissionWorker" => "Firmowid.Ash.Ksef.Workers.SubmissionWorker",
    "Firmowid.Ksef.FetchWorker" => "Firmowid.Ash.Ksef.Workers.FetchWorker",
    "Firmowid.Ksef.FetchDispatcher" => "Firmowid.Ash.Ksef.Workers.FetchDispatcher"
  }

  def up do
    if oban_table_exists?() do
      for {old_name, new_name} <- @worker_renames do
        execute """
        UPDATE oban.oban_jobs
        SET worker = '#{new_name}'
        WHERE worker = '#{old_name}'
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
