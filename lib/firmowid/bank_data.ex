defmodule Firmowid.BankData do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.BankData.ApiClient
  alias Firmowid.BankData.Requisition
  alias Firmowid.BankData.Transaction
  alias Firmowid.BankData.Worker
  alias Firmowid.Billing
  alias Firmowid.Finances
  alias Firmowid.Repo

  require Logger

  @requisition_broadcast_topic "requisition_status"

  def authorize(:create_requisition, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  @doc """
  Subscribe to requisition status updates for the given organization.
  """
  def subscribe_requisition_updates(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@requisition_broadcast_topic}:#{organization_id}"
    )
  end

  @doc """
  Broadcast requisition status update to subscribers.
  """
  def broadcast_requisition_status(organization_id, requisition_id, status) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@requisition_broadcast_topic}:#{organization_id}",
      {:requisition_status_update,
       %{
         requisition_id: requisition_id,
         status: status
       }}
    )
  end

  @doc """
  Broadcast requisition status update to subscribers.
  """
  def broadcast_requisition_status(organization_id, requisition_id, status, message) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@requisition_broadcast_topic}:#{organization_id}",
      {:requisition_status_update,
       %{
         requisition_id: requisition_id,
         status: status,
         message: message
       }}
    )
  end

  def list_requisitions(organization_id) do
    Requisition
    |> Repo.all(organization_id: organization_id)
    |> Repo.preload(:bank_accounts, organization_id: organization_id)
  end

  @doc """
  Fetch requisition by id, returning {:ok, requisition} or {:error, :not_found}.
  Allows passing Repo options in opts.
  """
  def get_requisition(requisition_id, opts \\ []) do
    case Repo.get(Requisition, requisition_id, opts) do
      nil -> {:error, :not_found}
      %Requisition{} = req -> {:ok, req}
    end
  end

  @doc """
  Mark requisition as accepted.

  Note: The billing counter increment happens outside the update transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful requisition acceptance over counter accuracy.
  If the increment fails, a warning is logged but the requisition is still accepted.
  Counter drift is acceptable for soft limit tracking.
  """
  def accept_requisition(%Requisition{} = requisition) do
    result =
      requisition
      |> Requisition.changeset(%{status: :accepted})
      |> Repo.update()

    with {:ok, accepted_requisition} <- result do
      case Billing.increment(accepted_requisition.organization_id, :bank_connections) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to increment bank_connections limit: #{inspect(reason)}")
      end
    end

    result
  end

  @doc """
  Mark requisition as rejected.

  Note: The billing counter decrement happens outside the update transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful requisition rejection over counter accuracy.
  If the decrement fails, a warning is logged but the requisition is still rejected.
  Counter drift is acceptable for soft limit tracking.
  """
  def reject_requisition(%Requisition{} = requisition) do
    was_accepted = requisition.status == :accepted

    result =
      requisition
      |> Requisition.changeset(%{status: :rejected})
      |> Repo.update()

    with {:ok, rejected} <- result, true <- was_accepted do
      case Billing.decrement(rejected.organization_id, :bank_connections) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to decrement bank_connections limit: #{inspect(reason)}")
      end
    end

    result
  end

  @doc """
  List available institutions (banks) for a given country.
  Uses GoCardless API.
  """
  def get_available_institutions_for_country(country) do
    ApiClient.get_available_institutions_for_country(country)
  end

  @doc """
  Get requisition status from GoCardless API.
  """
  @spec get_requisition_status(binary()) :: {:ok, binary()} | {:error, term()}
  def get_requisition_status(requisition_id) do
    case ApiClient.get_requisition(requisition_id) do
      {:ok, %{"status" => status}} -> {:ok, status}
      {:ok, other} -> {:error, {:unexpected_response, other}}
      {:error, _} = error -> error
    end
  end

  @doc """
  Create a new requisition for a given institution, max transaction days, redirect URL and
  organization ID.
  """
  @spec create_requisition(binary(), integer(), binary(), binary()) ::
          {:ok, binary()} | {:error, term()}
  def create_requisition(institution_id, max_transaction_days, organization_id, redirect_url) do
    with {:ok, requisition} <-
           ApiClient.create_requisition(
             institution_id,
             max_transaction_days,
             redirect_url
           ),
         {:ok, _} <-
           Repo.insert(%Requisition{
             id: requisition["id"],
             status: :pending,
             organization_id: organization_id
           }) do
      {:ok, requisition["link"]}
    end
  end

  @doc """
  Fetch a bank account by id.
  """
  @spec get_bank_account(binary(), Keyword.t()) ::
          {:ok, Finances.BankAccount.t()} | {:error, :not_found}
  def get_bank_account(bank_account_id, opts \\ []) do
    case Repo.get(Finances.BankAccount, bank_account_id, opts) do
      nil -> {:error, :not_found}
      %Finances.BankAccount{} = bank_account -> {:ok, bank_account}
    end
  end

  @doc """
  If used just with an organization_id, this will use one from Process.
  From e.g. Oban workers, pass also :skip_organization_id to avoid getting an
  error.

  But be careful of doing that in "userland"!
  """

  # Deprecated: the variant with :skip_organization_id is removed to enforce org scoping.
  # Callers should set the process org with Repo.put_org_id/1 and invoke sync_bank_account/1.

  def sync_bank_account(bank_account_id) do
    with {:ok, bank_account} <- get_bank_account(bank_account_id),
         {:ok, booked_transactions} <-
           ApiClient.get_booked_transactions_for_account(bank_account.gocardless_id),
         {:ok, _} <-
           upsert_booked_transactions(
             booked_transactions,
             bank_account_id,
             bank_account.organization_id
           ) do
      :ok
    end
  end

  def list_bank_accounts do
    from(b in Finances.BankAccount,
      order_by: [b.inserted_at, b.id]
    )
    |> Repo.all()
    |> Repo.preload(:requisition)
  end

  @doc """
  Determine if a bank account should be considered 'broken'.
  An account is broken if its most recent sync job was discarded after exhausting all retry attempts,
  or if it was cancelled with a permanent failure reason (expired_eua, forbidden).
  """
  def bank_account_broken?(bank_account_id) do
    query =
      from j in Oban.Job,
        where:
          fragment("args->>'name' = ?", "bank_account_sync") and
            fragment("args->>'bank_account_id' = ?", ^to_string(bank_account_id)),
        order_by: [desc: fragment("COALESCE(?, ?)", j.attempted_at, j.inserted_at)],
        limit: 1

    case Repo.one(query, oban_jobs: true) do
      # Job discarded after exhausting all attempts
      %{state: "discarded", attempt: attempt, max_attempts: max_attempts}
      when attempt >= max_attempts ->
        true

      # Job cancelled with permanent failure (expired_eua, forbidden, etc)
      %{state: "cancelled"} ->
        true

      # Any other state (completed, available, executing, etc) or no jobs found
      _ ->
        false
    end
  end

  @doc """
  Determine if a bank account has at least one successful sync job (state: completed).
  """
  def bank_account_has_success?(bank_account_id) do
    Oban.Job
    |> where(
      [j],
      fragment("args->>'name' = ?", "bank_account_sync") and
        fragment("args->>'bank_account_id' = ?", ^to_string(bank_account_id)) and
        j.state == ^"completed"
    )
    |> limit(1)
    |> Repo.all(oban_jobs: true)
    |> Enum.any?()
  end

  defp upsert_booked_transactions(booked_transactions, bank_account_id, organization_id) do
    booked_transactions
    |> Enum.map(fn transaction_from_api ->
      converted_transaction =
        transaction_from_api
        |> Transaction.map_camel_to_snake()
        |> Transaction.flatten_api_response()
        |> Transaction.changeset()
        |> Ecto.Changeset.apply_changes()

      converted_transaction
      |> Map.merge(%{bank_account_id: bank_account_id, organization_id: organization_id})
      |> Map.from_struct()
    end)
    |> Finances.create_or_update_transactions()

    {:ok, nil}
  end

  def create_or_update_bank_accounts_for_requisition(requisition_id, organization_id) do
    with {:ok, accounts} <- ApiClient.get_accounts_for_requisition(requisition_id) do
      bank_accounts =
        Enum.map(accounts, fn account ->
          Finances.create_bank_account(%{
            iban: account["iban"],
            gocardless_id: account["id"],
            owner_name: account["ownerName"],
            institution_id: account["institution_id"],
            institution_name: account["institution"]["name"],
            currency: account["currency"],
            name: account["name"],
            organization_id: organization_id,
            requisition_id: requisition_id
          })
        end)

      {:ok, bank_accounts}
    end
  end

  @doc """
  Mark all stale pending requisitions (inserted before cutoff) as rejected using a single
  UPDATE query wrapped in a transaction. After removal, schedule an Oban
  deletion job.
  """
  def cleanup_reject_stale_pending_and_delete_remote(cutoff_dt, organization_id) do
    query =
      from(r in Requisition)
      |> where([r], r.status == ^:pending and r.inserted_at < ^cutoff_dt)
      |> select([r], r.id)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update_all(:reject, query, [set: [status: :rejected]], organization_id: organization_id)
      |> Ecto.Multi.run(:enqueue_remote_deletes, fn _repo, %{reject: {_, ids}} ->
        jobs =
          Enum.map(ids, fn id ->
            Worker.new(%{
              name: "delete_remote_requisition",
              requisition_id: id
            })
          end)

        Repo.put_org_id(organization_id)

        try do
          _ = Firmowid.Oban.insert_all(jobs, [])
        after
          Repo.drop_org_id()
        end

        {:ok, :enqueued}
      end)

    case Repo.transact(multi, organization_id: organization_id) do
      {:ok, %{reject: {count, _}}} ->
        count

      {:error, _op, _reason, _changes} ->
        0
    end
  end

  @doc """
  Delete all orphaned requisitions (no bank accounts) inserted before cutoff with a single
  DELETE query wrapped in a transaction. After commit, best-effort delete remote
  requisitions. Returns the number of rows deleted.
  """
  def cleanup_delete_orphaned_requisitions(cutoff_dt, organization_id) do
    sub =
      from(b in Finances.BankAccount,
        where: b.requisition_id == parent_as(:req).id,
        select: 1
      )

    query =
      from(r in Requisition, as: :req)
      |> where([r], r.inserted_at < ^cutoff_dt)
      |> where([r], not exists(subquery(sub)))
      |> select([r], r.id)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(:delete_orphaned, query, organization_id: organization_id)
      |> Ecto.Multi.run(:enqueue_remote_deletes, fn _repo, %{delete_orphaned: {_, ids}} ->
        jobs =
          Enum.map(ids, fn id ->
            Worker.new(%{
              name: "delete_remote_requisition",
              requisition_id: id
            })
          end)

        Repo.put_org_id(organization_id)

        try do
          _ = Firmowid.Oban.insert_all(jobs, [])
        after
          Repo.drop_org_id()
        end

        {:ok, :enqueued}
      end)

    case Repo.transact(multi, organization_id: organization_id) do
      {:ok, %{delete_orphaned: {count, _}}} ->
        count

      {:error, _op, _reason, _changes} ->
        0
    end
  end

  @doc """
  Best-effort delete remote requisitions for all local requisitions that have at least one
  bank account and were inserted before cutoff. Local rows are preserved. Returns the
  number of remote delete attempts performed.
  """
  def cleanup_delete_expired_remote_requisitions(cutoff_dt, organization_id) do
    ids_query =
      from(r in Requisition)
      |> join(:left, [r], b in assoc(r, :bank_accounts))
      |> where([r, b], r.inserted_at < ^cutoff_dt and not is_nil(b.id))
      |> select([r], r.id)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.all(:ids, ids_query, organization_id: organization_id)
      |> Ecto.Multi.run(:enqueue_remote_deletes, fn _repo, %{ids: ids} ->
        jobs =
          Enum.map(ids, fn id ->
            Worker.new(%{
              name: "delete_remote_requisition",
              requisition_id: id
            })
          end)

        Repo.put_org_id(organization_id)

        try do
          _ = Firmowid.Oban.insert_all(jobs, [])
        after
          Repo.drop_org_id()
        end

        {:ok, :enqueued}
      end)

    case Repo.transact(multi, organization_id: organization_id) do
      {:ok, %{ids: ids}} -> length(ids || [])
      {:error, _op, _reason, _changes} -> 0
    end
  end
end
