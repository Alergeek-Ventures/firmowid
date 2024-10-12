defmodule Firmowid.BankData do
  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.Finances
  alias Firmowid.BankData.Requisition
  alias Firmowid.BankData.ApiClient

  def get_available_accounts_for_country(country) do
    ApiClient.get_available_accounts_for_country(country)
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
             requisition_id: requisition["id"],
             status: :pending,
             organization_id: organization_id
           }) do
      {:ok, requisition["link"]}
    end
  end

  def confirm_requisition(gocardless_requisition_id, organization_id) do
    requisition_from_db =
      Repo.get_by(
        Requisition,
        [requisition_id: gocardless_requisition_id],
        organization_id: organization_id
      )

    case requisition_from_db do
      nil ->
        {:error, :not_found}

      _ ->
        with requisition_from_api <-
               ApiClient.get_requisition(gocardless_requisition_id) do
          if requisition_from_api["status"] == "LN" do
            Repo.update!(
              Requisition.changeset(requisition_from_db, %{
                status: :accepted
              })
            )

            create_or_update_bank_accounts_for_requisition(
              gocardless_requisition_id,
              requisition_from_db.id,
              organization_id
            )

            {:ok, requisition_from_api}
          else
            {:error, requisition_from_api}
          end
        end
    end
  end

  def sync_requisition(firmowid_requisition_id, organization_id) do
    gocardless_requisition_id =
      Repo.get_by!(Requisition, [id: firmowid_requisition_id], organization_id: organization_id).requisition_id

    accounts = ApiClient.get_accounts_for_requisition(gocardless_requisition_id)

    accounts
    |> Enum.each(fn go_cardless_account ->
      all_firmowid_accounts = Finances.list_bank_accounts(organization_id)

      bank_account =
        all_firmowid_accounts
        |> Enum.find(fn a -> a.iban == go_cardless_account["iban"] end)

      booked_transactions =
        ApiClient.get_transactions_for_account(go_cardless_account["id"])

      Enum.each(booked_transactions, fn t ->
        Finances.create_or_update_imported_transaction(%{
          transaction_id: t["transactionId"],
          internal_transaction_id: t["internalTransactionId"],
          debtor_name: t["debtorName"] || "N/A",
          debtor_account: t["debtorAccount"]["iban"] || "N/A",
          creditor_name: t["creditorName"] || "N/A",
          creditor_account: t["creditorAccount"]["iban"] || "N/A",
          transaction_amount:
            t["transactionAmount"]["amount"]
            |> String.to_float(),
          transaction_currency: t["transactionAmount"]["currency"],
          booking_date: t["bookingDate"] |> Date.from_iso8601!(),
          value_date: t["valueDate"] |> Date.from_iso8601!(),
          remittance_information_unstructured: t["remittanceInformationUnstructured"],
          bank_account_id: bank_account.id,
          organization_id: organization_id
        })
      end)
    end)
  end

  defp create_or_update_bank_accounts_for_requisition(
         gocardless_requisition_id,
         firmowid_requisition_id,
         organization_id
       ) do
    ApiClient.get_accounts_for_requisition(gocardless_requisition_id)
    |> Enum.each(fn account ->
      Firmowid.Finances.create_bank_account(%{
        iban: account["iban"],
        organization_id: organization_id,
        requisition_id: firmowid_requisition_id
      })
    end)
  end

  def delete_requisition(requisition_id, organization_id) do
    with requisition <- Repo.get(Requisition, requisition_id, organization_id: organization_id),
         {:ok, _} <- ApiClient.delete_requisition(requisition.requisition_id),
         {:ok, _} <- Repo.delete(requisition, organization_id: organization_id) do
      {:ok, requisition}
    end
  end
end
