defmodule Firmowid.BankData.Worker do
  @moduledoc false
  use Oban.Worker,
    queue: :bank_data,
    max_attempts: 15

  alias Firmowid.BankData
  alias Firmowid.BankData.Requisition
  alias Firmowid.Repo

  require Logger

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "name" => "bank_account_sync",
            "bank_account_id" => bank_account_id,
            "organization_id" => organization_id
          }
        } = job
      ) do
    Logger.info("Syncing bank account #{bank_account_id}")

    Sentry.Context.add_breadcrumb(%{
      category: "bank_account_sync",
      data: %{bank_account_id: bank_account_id, organization_id: organization_id, job_id: job.id}
    })

    Repo.put_org_id(organization_id)

    try do
      case BankData.sync_bank_account(bank_account_id) do
        :ok ->
          :ok

        {:error, :not_found} ->
          Logger.warning("Bank account #{bank_account_id} not found; cancelling sync job")
          {:cancel, :not_found}

        {:error, :rate_limited} ->
          Logger.warning("Rate limited while fetching transactions for bank account #{bank_account_id}")

          {:snooze, 86_400}

        {:error, reason} ->
          Logger.error(
            "Unexpected error while fetching transactions for bank account #{bank_account_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    after
      Repo.drop_org_id()
    end
  end

  def perform(%Oban.Job{args: %{"name" => "dispatch_sync_jobs_for_all_bank_accounts"}}) do
    Firmowid.Finances.get_bank_accounts_for_sync()
    |> Enum.group_by(& &1.organization_id)
    |> Enum.each(fn {organization_id, accounts} ->
      changesets =
        accounts
        |> Enum.map(&%{bank_account_id: &1.id, organization_id: organization_id, name: "bank_account_sync"})
        |> Enum.map(&__MODULE__.new/1)

      Repo.put_org_id(organization_id)

      try do
        _ = Firmowid.Oban.insert_all(changesets, [])
      after
        Repo.drop_org_id()
      end
    end)

    :ok
  end

  def perform(
        %Oban.Job{
          attempt: attempt,
          args: %{
            "name" => "check_requisition_status",
            "requisition_id" => requisition_id,
            "organization_id" => organization_id
          }
        } = job
      ) do
    Logger.info("Checking requisition status for #{requisition_id}, attempt #{attempt}")

    Sentry.Context.add_breadcrumb(%{
      category: "check_requisition_status",
      data: %{requisition_id: requisition_id, organization_id: organization_id, job_id: job.id}
    })

    Repo.put_org_id(organization_id)

    try do
      with {:ok, %Requisition{} = requisition_db} <- BankData.get_requisition(requisition_id),
           {:ok, status} <- BankData.get_requisition_status(requisition_id) do
        handle_requisition_status(status, requisition_db, organization_id, attempt)
      else
        {:error, :not_found} ->
          Logger.error("Requisition #{requisition_id} not found for organization #{organization_id}")

          {:cancel, :not_found}

        {:error, reason} ->
          Logger.error("Failed to fetch requisition status: #{inspect(reason)}")
          {:error, reason}
      end
    after
      Repo.drop_org_id()
    end
  end

  def perform(%Oban.Job{args: %{"name" => "delete_remote_requisition", "requisition_id" => requisition_id}}) do
    Logger.info("Deleting remote requisition #{requisition_id}")

    case Firmowid.BankData.ApiClient.delete_requisition(requisition_id) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete remote requisition #{requisition_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Unknown job args: #{inspect(args)}")
    {:cancel, :unknown_job}
  end

  # attempt starts at 1 and increments each execution
  defp calculate_backoff(0), do: 30
  defp calculate_backoff(1), do: 70
  defp calculate_backoff(2), do: 100
  defp calculate_backoff(3), do: 200
  defp calculate_backoff(4), do: 300
  defp calculate_backoff(5), do: 450
  defp calculate_backoff(_), do: 600

  defp handle_requisition_status("LN", %Requisition{} = requisition_db, organization_id, _attempt) do
    Logger.info("Requisition #{requisition_db.id} is now linked")

    with {:ok, _} <- BankData.accept_requisition(requisition_db),
         {:ok, bank_accounts} <-
           BankData.create_or_update_bank_accounts_for_requisition(
             requisition_db.id,
             organization_id
           ) do
      bank_accounts
      |> Enum.map(&%{bank_account_id: &1.id, organization_id: organization_id, name: "bank_account_sync"})
      |> Enum.group_by(& &1.organization_id)
      |> Enum.each(fn {org_id, jobs} ->
        changesets = Enum.map(jobs, &__MODULE__.new/1)

        Repo.put_org_id(org_id)

        try do
          _ = Firmowid.Oban.insert_all(changesets, [])
        after
          Repo.drop_org_id()
        end
      end)

      BankData.broadcast_requisition_status(
        organization_id,
        requisition_db.id,
        :linked
      )

      :ok
    else
      {:error, reason} ->
        Logger.error(
          "Failed to accept requisition or create/update bank accounts for #{requisition_db.id}: #{inspect(reason)}"
        )

        BankData.broadcast_requisition_status(
          organization_id,
          requisition_db.id,
          :error
        )

        {:error, reason}
    end
  end

  @processing_statuses ~w(CR GC UA SA GA)
  @requisition_timeout_attempts 20

  defp handle_requisition_status(status, %Requisition{} = requisition_db, organization_id, attempt)
       when status in @processing_statuses do
    Logger.info("Requisition #{requisition_db.id} still processing with status: #{status}")

    # Broadcast processing status on first attempt
    if attempt == 1 do
      BankData.broadcast_requisition_status(
        organization_id,
        requisition_db.id,
        :processing
      )
    end

    if attempt > @requisition_timeout_attempts do
      Logger.error("Requisition #{requisition_db.id} timed out after #{attempt} attempts")

      BankData.broadcast_requisition_status(
        organization_id,
        requisition_db.id,
        :timeout
      )

      case BankData.reject_requisition(requisition_db) do
        {:ok, _} -> {:cancel, :timeout}
        {:error, reason} -> {:error, reason}
      end
    else
      {:snooze, calculate_backoff(attempt)}
    end
  end

  defp handle_requisition_status("RJ", %Requisition{} = requisition_db, organization_id, _attempt) do
    Logger.info("Requisition #{requisition_db.id} was rejected")

    BankData.broadcast_requisition_status(
      organization_id,
      requisition_db.id,
      :rejected
    )

    case BankData.reject_requisition(requisition_db) do
      {:ok, _} -> {:cancel, :rejected}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_requisition_status("EX", %Requisition{} = requisition_db, organization_id, _attempt) do
    Logger.info("Requisition #{requisition_db.id} has expired")

    BankData.broadcast_requisition_status(
      organization_id,
      requisition_db.id,
      :expired
    )

    {:cancel, :expired}
  end

  defp handle_requisition_status(unknown_status, %Requisition{} = requisition_db, _organization_id, _attempt) do
    Logger.error("Unknown requisition status: #{unknown_status} for #{requisition_db.id}")
    {:error, {:unknown_status, unknown_status}}
  end
end
