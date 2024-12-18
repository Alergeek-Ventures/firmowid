defmodule Firmowid.BankData.ApiClient do
  alias Firmowid.BankData.TokenManager

  def get_available_accounts_for_country(country) do
    {:ok, access_token} = get_access_token()

    Req.get!("https://bankaccountdata.gocardless.com/api/v2/institutions/?country=#{country}",
      auth: {:bearer, access_token}
    )
    |> Map.get(:body)
  end

  def get_requisition(requisition_id) do
    {:ok, access_token} = get_access_token()

    requisition_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      )

    requisition_response.body
  end

  def create_requisition(institution_id, max_transaction_days, redirect_url) do
    with {:ok, access_token} <- get_access_token(),
         %{body: %{"id" => agreement_id}} <-
           Req.post!(
             "https://bankaccountdata.gocardless.com/api/v2/agreements/enduser/",
             auth: {:bearer, access_token},
             json: %{
               institution_id: institution_id,
               max_historical_days: min(max_transaction_days, 90),
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
    {:ok, access_token} = get_access_token()

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
    {:ok, access_token} = get_access_token()

    institutions_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/institutions?country=pl",
        auth: {:bearer, access_token}
      )

    institutions_response.body
  end

  def get_transactions_for_account(account_id) do
    {:ok, access_token} = get_access_token()

    accounts_transaction_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/accounts/#{account_id}/transactions",
        auth: {:bearer, access_token}
      )

    accounts_transaction_response.body["transactions"]["booked"]
  end

  def delete_requisition(requisition_id) do
    {:ok, access_token} = get_access_token()

    requisition =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      )

    Req.delete!(
      "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
      auth: {:bearer, access_token}
    )

    Req.delete!(
      "https://bankaccountdata.gocardless.com/api/v2/agreements/#{requisition.body["agreement"]}",
      auth: {:bearer, access_token}
    )

    {:ok, requisition}
  end

  defp get_access_token() do
    token = GenServer.call(TokenManager, :get_access_token)

    if token == nil do
      raise "Access token is not set"
    end

    {:ok, token}
  end
end
