defmodule Firmowid.BankData.ApiClient do
  alias Firmowid.BankData.TokenManager

  def get_available_institutions_for_country(country) do
    {:ok, access_token} = get_access_token()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/institutions/?country=#{country}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :bank_data_institutions, []))

    with {:ok, response} <- Req.get(options) do
      response |> Map.get(:body)
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_requisition(requisition_id) do
    {:ok, access_token} = get_access_token()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :bank_data_requisition, []))

    with {:ok, response} <- Req.get(options) do
      response |> Map.get(:body)
    else
      {:error, error} -> {:error, error}
    end
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

  def get_institution(go_cardless_institution_id) do
    {:ok, access_token} = get_access_token()

    options =
      [
        url:
          "https://bankaccountdata.gocardless.com/api/v2/institutions/#{go_cardless_institution_id}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :bank_data_institution, []))

    with {:ok, response} <- Req.get(options) do
      {:ok, response |> Map.get(:body)}
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_account_details(gocardless_account_id) do
    {:ok, access_token} = get_access_token()

    options =
      [
        url:
          "https://bankaccountdata.gocardless.com/api/v2/accounts/#{gocardless_account_id}/details",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :bank_data_requisition, []))

    with {:ok, response} <- Req.get(options) do
      {:ok, response |> Map.get(:body) |> Map.get("account")}
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_account_status(gocardless_account_id) do
    {:ok, access_token} = get_access_token()

    options =
      [
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :bank_data_account, []))

    with {:ok, account_response} <-
           Req.get(
             options
             |> Keyword.put(
               :url,
               "https://bankaccountdata.gocardless.com/api/v2/accounts/#{gocardless_account_id}"
             )
           ) do
      {:ok, account_response |> Map.get(:body)}
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_accounts_for_requisition(requisition_id) do
    {:ok, access_token} = get_access_token()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :bank_data_requisition, []))

    with {:ok, response} <- Req.get(options),
         accounts <- Map.get(response.body, "accounts", []) do
      accounts
      |> Enum.map(fn account ->
        with {:ok, account_response} <-
               get_account_status(account),
             {:ok, account_details} <-
               get_account_details(account) do
          {:ok, institution} = get_institution(account_response["institution_id"])

          Map.merge(account_response, account_details)
          |> Map.put(
            "institution",
            institution
          )
        else
          {:error, error} -> {:error, error}
        end
      end)
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_booked_transactions_for_account(account_id) do
    {:ok, access_token} = get_access_token()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/accounts/#{account_id}/transactions",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :bank_data_transactions, []))

    with %{status: 200, body: accounts_transaction} <- Req.get!(options) do
      accounts_transaction
      |> Map.get("transactions")
      |> Map.get("booked")
    else
      error -> error
    end
  end

  def delete_requisition(requisition_id) do
    {:ok, access_token} = get_access_token()

    with {:ok, requisition} <-
           Req.get(
             "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
             auth: {:bearer, access_token}
           ),
         {:ok, _} <-
           Req.delete(
             "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
             auth: {:bearer, access_token}
           ),
         {:ok, _} <-
           Req.delete(
             "https://bankaccountdata.gocardless.com/api/v2/agreements/#{requisition.body["agreement"]}",
             auth: {:bearer, access_token}
           ) do
      {:ok, requisition}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp get_access_token() do
    token = GenServer.call(TokenManager, :get_access_token)

    if token == nil do
      raise "Access token is not set"
    end

    {:ok, token}
  end
end
