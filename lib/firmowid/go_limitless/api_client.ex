defmodule Firmowid.GoLimitless.ApiClient do
  @moduledoc """
  The GoLimitless ApiClient context.
  """
  alias Firmowid.GoLimitless.TokenManager

  def get_accounts_for_requisition(requisition_id) do
    access_token = get_access_token()

    accounts_response =
      Req.get!(
        "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      )

    accounts_response.body["accounts"]
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

  defp get_access_token() do
    TokenManager.get_access_token()
  end
end
