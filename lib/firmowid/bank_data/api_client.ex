defmodule Firmowid.BankData.ApiClient do
  alias Firmowid.BankData.TokenManager

  def get_available_accounts_for_country(country) do
    access_token = get_access_token()

    Req.get!("https://bankaccountdata.gocardless.com/api/v2/institutions/?country=#{country}",
      auth: {:bearer, access_token}
    )
    |> Map.get(:body)
  end

  def get_requisition(requisition_id) do
    access_token = get_access_token()

    requisition_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      )

    requisition_response.body
  end

  def create_requisition(institution_id, max_transaction_days, redirect_url) do
    access_token = get_access_token()

    with %{body: %{"id" => agreement_id}} <-
           Req.post!(
             "https://bankaccountdata.gocardless.com/api/v2/agreements/enduser/",
             auth: {:bearer, access_token},
             json: %{
               institution_id: institution_id,
               max_historical_days: max(max_transaction_days, 90),
               access_valid_for_days: 90,
               access_scope: ["balances", "details", "transactions"]
             }
           ),
         %{body: requisition_body, status: 201} <-
           Req.post!(
             "https://bankaccountdata.gocardless.com/api/v2/requisitions/",
             auth: {:bearer, access_token},
             json: %{
               redirect: redirect_url,
               institution_id: institution_id,
               agreement: agreement_id,
               user_language: "PL"
             }
           ) do
      requisition_body
    end
  end

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

  def get_available_institutions() do
    access_token = get_access_token()

    institutions_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/institutions?country=pl",
        auth: {:bearer, access_token}
      )

    institutions_response.body
  end

  def get_transactions_for_account(account_id) do
    access_token = get_access_token()

    accounts_transaction_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/accounts/#{account_id}/transactions",
        auth: {:bearer, access_token}
      )

    accounts_transaction_response.body["transactions"]["booked"]
  end

  defp get_access_token() do
    TokenManager.get_access_token()
  end
end
