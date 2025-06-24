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
            job: job
          }
        })

        Firmowid.BankData.sync_bank_account(bank_account_id, :skip_organization_id)

      %{"name" => "schedule_sync"} ->
        Firmowid.Finances.get_bank_accounts_for_sync()
        |> Enum.map(& &1.id)
        |> Enum.each(&schedule_bank_account_sync/1)
    end

    :ok
  end

  defp schedule_bank_account_sync(bank_account_id) do
    %{bank_account_id: bank_account_id, name: "bank_account_sync"}
    |> Firmowid.BankData.Worker.new()
    |> Oban.insert()
  end
end
