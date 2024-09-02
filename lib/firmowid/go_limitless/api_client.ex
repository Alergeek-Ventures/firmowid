defmodule Firmowid.GoLimitless.ApiClient do
  @moduledoc """
  The GoLimitless ApiClient context.
  """
  alias Firmowid.GoLimitless.TokenManager

  alias Firmowid.Finances

  def get_accounts_for_requisition(requisition_id) do
    access_token = get_access_token()

    accounts_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      )

    accounts = Map.get(accounts_response.body, "accounts", [])

    accounts
    |> Enum.map(fn account ->
      Req.get!("https://bankaccountdata.gocardless.com/api/v2/accounts/#{account}",
        auth: {:bearer, access_token}
      )
      |> Map.get(:body)
    end)
  end

  def create_requisition(selected_institution_id) do
    access_token = get_access_token()

    agreement_response =
      Req.post!(
        "https://bankaccountdata.gocardless.com/api/v2/agreements/enduser/",
        auth: {:bearer, access_token},
        json: %{
          institution_id: selected_institution_id,
          max_historical_days: 365,
          access_valid_for_days: 90,
          access_scope: ["balances", "details", "transactions"]
        }
      )

    requisition_response =
      Req.post!(
        "https://bankaccountdata.gocardless.com/api/v2/requisitions/",
        auth: {:bearer, access_token},
        json: %{
          redirect: "http://app.firmowid.pl/limitless_callback",
          institution_id: selected_institution_id,
          agreement: agreement_response.body["id"],
          user_language: "PL"
        }
      )

    requisition_response.body
  end

  def get_available_institutions() do
    access_token = get_access_token()

    institutions_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/institutions?country=pl",
        auth: {:bearer, access_token}
      )

    institutions_response.body
  end

  def sync_transaction_for_account(iban, requisition_id) do
    access_token = get_access_token()

    accounts_list =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      )

    dbg(accounts_list.body)

    gocardless_account_id =
      accounts_list.body["accounts"]
      |> Enum.find(fn account_id ->
        account_data =
          Req.get!("https://bankaccountdata.gocardless.com/api/v2/accounts/#{account_id}",
            auth: {:bearer, access_token}
          )

        dbg(account_data.body)

        account_data.body["iban"] == iban
      end)

    dbg(gocardless_account_id)

    all_accounts = Finances.list_bank_accounts()

    dbg(all_accounts)

    bank_account =
      all_accounts
      |> Enum.find(fn a -> a.iban == iban end)

    dbg(bank_account.iban)

    accounts_transaction_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/accounts/#{gocardless_account_id}/transactions",
        auth: {:bearer, access_token}
      )

    booked_transactions = accounts_transaction_response.body["transactions"]["booked"]

    dbg(length(booked_transactions))

    Enum.each(booked_transactions, fn t ->
      Finances.create_imported_transaction(%{
        transaction_id: t["transactionId"],
        internal_transaction_id: t["internalTransactionId"],
        debtor_name: t["debtorName"],
        debtor_account: t["debtorAccount"]["iban"],
        creditor_name: t["creditorName"],
        creditor_account: t["creditorAccount"]["iban"],
        transaction_amount:
          t["transactionAmount"]["amount"]
          |> String.to_float(),
        transaction_currency: t["transactionAmount"]["currency"],
        booking_date: t["bookingDate"] |> Date.from_iso8601!(),
        value_date: t["valueDate"] |> Date.from_iso8601!(),
        remittance_information_unstructured: t["remittanceInformationUnstructured"],
        bank_account_id: bank_account.id
      })
    end)
  end

  defp get_access_token() do
    TokenManager.get_access_token()
  end
end
