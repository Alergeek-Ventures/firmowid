defmodule Firmowid.BankData do
  import Ecto.Query, warn: false

  require Logger

  alias Firmowid.Repo
  alias Firmowid.Finances
  alias Firmowid.BankData.Requisition
  alias Firmowid.BankData.ApiClient
  alias Firmowid.BankData.Transaction

  @behaviour Bodyguard.Policy

  def authorize(:create_requisition, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  def list_requisitions(organization_id) do
    Repo.all(Requisition, organization_id: organization_id)
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
  """
  def accept_requisition(%Requisition{} = requisition) do
    requisition
    |> Requisition.changeset(%{status: :accepted})
    |> Repo.update()
  end

  @doc """
  Mark requisition as rejected.
  """
  def reject_requisition(%Requisition{} = requisition) do
    requisition
    |> Requisition.changeset(%{status: :rejected})
    |> Repo.update()
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

  @spec get_requisition_status(binary()) ::
          {:ok, binary()} | {:error, {:unexpected_response, map()}}
  def get_requisition_status(requisition_id) do
    case ApiClient.get_requisition(requisition_id) do
      %{"status" => status} -> {:ok, status}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  @doc """
  Create a new requisition for a given institution, max transaction days, redirect URL and
  organization ID.
  """
  @spec create_requisition(binary(), integer(), binary(), binary()) ::
          {:ok, binary()} | {:error, {:unexpected_response, map()}}
  def create_requisition(institution_id, max_transaction_days, organization_id, redirect_url) do
    with requisition <-
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
  def sync_bank_account(bank_account_id, :skip_organization_id) do
    with {:ok, bank_account} <- get_bank_account(bank_account_id, skip_organization_id: true) do
      Repo.put_org_id(bank_account.organization_id)
      result = sync_bank_account(bank_account_id)
      Repo.drop_org_id()
      result
    else
      error -> error
    end
  end

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
    else
      error -> error
    end
  end

  def list_bank_accounts() do
    Repo.all(
      from b in Finances.BankAccount,
        order_by: [b.inserted_at, b.id]
    )
    |> Repo.preload(:requisition)
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

  def create_or_update_bank_accounts_for_requisition(
        requisition_id,
        organization_id
      ) do
    bank_accounts =
      ApiClient.get_accounts_for_requisition(requisition_id)
      |> Enum.map(fn account ->
        bank_account =
          Firmowid.Finances.create_bank_account(%{
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

        bank_account
      end)

    {:ok, bank_accounts}
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
      |> Ecto.Multi.update_all(:reject, query, [set: [status: :rejected]],
        organization_id: organization_id
      )
      |> Ecto.Multi.run(:enqueue_remote_deletes, fn _repo, %{reject: {_, ids}} ->
        jobs =
          ids
          |> Enum.map(fn id ->
            Firmowid.BankData.Worker.new(%{
              name: "delete_remote_requisition",
              requisition_id: id
            })
          end)

        result = Firmowid.Oban.insert_all(jobs, skip_organization_id: true)

        case result do
          {:ok, _} -> {:ok, :enqueued}
          {:error, reason} -> {:error, reason}
        end
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
          ids
          |> Enum.map(fn id ->
            Firmowid.BankData.Worker.new(%{
              name: "delete_remote_requisition",
              requisition_id: id
            })
          end)

        result = Firmowid.Oban.insert_all(jobs, skip_organization_id: true)

        case result do
          {:ok, _} -> {:ok, :enqueued}
          {:error, reason} -> {:error, reason}
        end
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
      |> where([r, b], r.inserted_at < ^cutoff_dt and is_nil(b.id))
      |> select([r], r.id)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.all(:ids, ids_query, organization_id: organization_id)
      |> Ecto.Multi.run(:enqueue_remote_deletes, fn _repo, %{ids: ids} ->
        jobs =
          ids
          |> Enum.map(fn id ->
            Firmowid.BankData.Worker.new(%{
              name: "delete_remote_requisition",
              requisition_id: id
            })
          end)

        result = Firmowid.Oban.insert_all(jobs, skip_organization_id: true)

        case result do
          {:ok, _} -> {:ok, :enqueued}
          {:error, reason} -> {:error, reason}
        end
      end)

    case Repo.transact(multi, organization_id: organization_id) do
      {:ok, %{ids: ids}} -> length(ids || [])
      {:error, _op, _reason, _changes} -> 0
    end
  end
end
