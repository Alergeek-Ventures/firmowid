defmodule Firmowid.BankData.Worker do
  use Oban.Worker, queue: :bank_data

  require Logger

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "bank_account_sync", "bank_account_id" => bank_account_id} ->
        Logger.info("Syncing bank account #{bank_account_id}")

        Sentry.Context.add_breadcrumb(%{
          category: "bank_account_sync",
          data: %{
            bank_account_id: bank_account_id,
            job_id: job.id
          }
        })

        Firmowid.BankData.sync_bank_account(bank_account_id, :skip_organization_id)

      %{"name" => "dispatch_sync_jobs_for_all_bank_accounts"} ->
        Firmowid.Finances.get_bank_accounts_for_sync()
        |> Enum.map(&%{bank_account_id: &1.id, name: "bank_account_sync"})
        |> Enum.map(&Firmowid.BankData.Worker.new/1)
        |> Firmowid.Oban.insert_all(skip_organization_id: true)
    end

    :ok
  end
end
