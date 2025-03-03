defmodule Firmowid.BankData do
  import Ecto.Query, warn: false

  require Logger

  alias Firmowid.Repo
  alias Firmowid.Accounts.User

  alias Firmowid.Finances
  alias Firmowid.BankData.Requisition
  alias Firmowid.BankData.ApiClient
  alias Firmowid.BankData.Transaction

  @behaviour Bodyguard.Policy

  def authorize(_, %User{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  def get_available_institutions_for_country(country) do
    ApiClient.get_available_institutions_for_country(country)
  end

  def list_requisitions(organization_id) do
    Repo.all(Requisition, organization_id: organization_id)
    |> Repo.preload(:bank_accounts, organization_id: organization_id)
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

  def confirm_requisition(requisition_id, organization_id) do
    requisition_from_db =
      Repo.get!(
        Requisition,
        requisition_id,
        organization_id: organization_id
      )

    case requisition_from_db do
      nil ->
        {:error, :not_found}

      _ ->
        with requisition_from_api <-
               ApiClient.get_requisition(requisition_id) do
          if requisition_from_api["status"] == "LN" do
            Repo.update!(
              Requisition.changeset(requisition_from_db, %{
                status: :accepted
              })
            )

            {:ok, bank_accounts} =
              create_or_update_bank_accounts_for_requisition(
                requisition_from_db.id,
                organization_id
              )

            # sync newly created accounts instantly
            # still want to leverage workers for it (maybe smarter in the
            # future)
            bank_accounts
            |> Enum.each(fn bank_account ->
              %{bank_account_id: bank_account.id, name: "bank_account_sync"}
              |> Firmowid.BankData.Worker.new()
              |> Oban.insert()
            end)

            {:ok, requisition_from_api}
          else
            {:error, requisition_from_api}
          end
        end
    end
  end

  @doc """
    If used just with an organization_id, this will use one from Process.
    From e.g. Oban workers, pass also :skip_organization_id to avoid getting an
    error. But be careful of doing that in "userland"!
  """
  def sync_bank_account(bank_account_id, :skip_organization_id) do
    bank_account =
      Finances.BankAccount
      |> Repo.get!(bank_account_id, skip_organization_id: true)

    Repo.put_org_id(bank_account.organization_id)

    sync_bank_account(bank_account_id)

    Repo.drop_org_id()
  end

  def sync_bank_account(bank_account_id) do
    bank_account =
      Finances.BankAccount
      |> Repo.get!(bank_account_id)

    with {:ok, booked_transactions} <-
           ApiClient.get_booked_transactions_for_account(bank_account.gocardless_id),
         {:ok, _} <-
           upsert_booked_transactions(
             booked_transactions,
             bank_account_id,
             bank_account.organization_id
           ) do
      {:ok, nil}
    else
      {:error, :rate_limited} ->
        Logger.error(
          "Rate limited while fetching transactions for bank account #{bank_account_id}"
        )

      {:error, error} ->
        Logger.error(
          "Unexpected error while fetching transactions for bank account #{bank_account_id}: #{inspect(error)}"
        )
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

  defp create_or_update_bank_accounts_for_requisition(
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
