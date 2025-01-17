defmodule Firmowid.BankData.Worker do
  use Oban.Worker, queue: :bank_data

  require Logger

  @impl Oban.Worker
  def perform(job) do
    case job.args do
      %{"name" => "bank_account_sync", "bank_account_id" => bank_account_id} ->
        Logger.info("Syncing bank account #{bank_account_id}")

        try do
          Firmowid.BankData.sync_bank_account(bank_account_id, :skip_organization_id)
        rescue
          error ->
            Sentry.capture_exception(error)
            Logger.error("Failed to sync bank account #{bank_account_id} #{inspect(error)}")

            # TODO: mark account as failing
        end

      # to work around Fly.io suspending the machines, every hour we
      # schedule a sync for all bank accounts
      # (when it wakes up it will start scheduling)
      %{"name" => "schedule_sync"} ->
        bank_accounts = Firmowid.Finances.get_bank_accounts_for_sync()

        bank_accounts
        |> Enum.map(& &1.id)
        |> Enum.each(&schedule_bank_account_sync/1)
    end

    :ok
  end

  defp schedule_bank_account_sync(bank_account_id) do
    # consistent sync times (for idempotency) - today at 11:55PM UTC
    today = Date.utc_today()
    eleven_am = ~T[11:00:00]
    {:ok, scheduled_at} = NaiveDateTime.new(today, eleven_am)

    %{bank_account_id: bank_account_id, name: "bank_account_sync"}
    |> Firmowid.BankData.Worker.new(
      scheduled_at: scheduled_at,
      # unique by args + timestamp (but scheduled_at instead of inserted_at), so idempotent!
      unique: [
        timestamp: :scheduled_at
      ]
    )
    |> Oban.insert()
  end
end
