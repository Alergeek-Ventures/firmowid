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

  def get_available_institutions_for_country(country) do
    ApiClient.get_available_institutions_for_country(country)
  end

  def list_requisitions(organization_id) do
    Repo.all(Requisition, organization_id: organization_id)
    |> Repo.preload(:bank_accounts, organization_id: organization_id)
  end

  @doc """
  Fetch requisition by id, returning {:ok, requisition} or {:error, :not_found}.
  Allows passing Repo options in opts.
  """
  def fetch_requisition(requisition_id, opts \\ []) do
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
  Get requisition status from API as {:ok, status} | {:error, reason}.
  """
  def get_requisition_status(requisition_id) do
    case ApiClient.get_requisition(requisition_id) do
      %{"status" => status} -> {:ok, status}
      other -> {:error, {:unexpected_response, other}}
    end
  end

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
    Fetch a bank account by id, returning {:ok, bank_account} or {:error, :not_found}.
    You can pass Repo options (e.g., skip_organization_id: true) via opts.
  """
  def fetch_bank_account(bank_account_id, opts \\ []) do
    case Repo.get(Finances.BankAccount, bank_account_id, opts) do
      nil -> {:error, :not_found}
      %Finances.BankAccount{} = bank_account -> {:ok, bank_account}
    end
  end

  @doc """
    If used just with an organization_id, this will use one from Process.
    From e.g. Oban workers, pass also :skip_organization_id to avoid getting an
    error. But be careful of doing that in "userland"!
  """
  def sync_bank_account(bank_account_id, :skip_organization_id) do
    with {:ok, bank_account} <- fetch_bank_account(bank_account_id, skip_organization_id: true) do
      Repo.put_org_id(bank_account.organization_id)
      result = sync_bank_account(bank_account_id)
      Repo.drop_org_id()
      result
    else
      error -> error
    end
  end

  def sync_bank_account(bank_account_id) do
    with {:ok, bank_account} <- fetch_bank_account(bank_account_id),
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

  def delete_requisition(requisition_id, organization_id) do
    with requisition <- Repo.get(Requisition, requisition_id, organization_id: organization_id),
         {:ok, _} <- ApiClient.delete_requisition(requisition_id),
         {:ok, _} <- Repo.delete(requisition, organization_id: organization_id) do
      {:ok, requisition}
    end
  end
end
