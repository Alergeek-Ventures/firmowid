defmodule Firmowid.BankData.ApiClient do
  alias Firmowid.BankData.TokenManager

  def get_available_institutions_for_country(country) do
    access_token = get_access_token!()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/institutions/?country=#{country}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_institutions))

    with {:ok, response} <- Req.get(options) do
      response |> Map.get(:body)
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_requisition(requisition_id) do
    access_token = get_access_token!()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_requisition))

    with {:ok, response} <- Req.get(options) do
      response |> Map.get(:body)
    else
      {:error, error} -> {:error, error}
    end
  end

  def create_requisition(institution_id, max_transaction_days, redirect_url) do
    access_token = get_access_token!()

    agreement_opts =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/agreements/enduser/",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_requisition))

    requisition_opts =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_requisition))

    with %{body: %{"id" => agreement_id}} <-
           Req.post!(
             Keyword.merge(agreement_opts,
               json: %{
                 institution_id: institution_id,
                 max_historical_days: min(max_transaction_days, 90),
                 access_valid_for_days: 90,
                 access_scope: ["balances", "details", "transactions"]
               }
             )
           ),
         %{body: requisition_body, status: 201} <-
           Req.post!(
             Keyword.merge(requisition_opts,
               json: %{
                 redirect: redirect_url,
                 institution_id: institution_id,
                 agreement: agreement_id,
                 user_language: "PL"
               }
             )
           ) do
      requisition_body
    end
  end

  def get_institution(go_cardless_institution_id) do
    access_token = get_access_token!()

    options =
      [
        url:
          "https://bankaccountdata.gocardless.com/api/v2/institutions/#{go_cardless_institution_id}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_institution))

    with {:ok, response} <- Req.get(options) do
      {:ok, response |> Map.get(:body)}
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_account_details(gocardless_account_id) do
    access_token = get_access_token!()

    options =
      [
        url:
          "https://bankaccountdata.gocardless.com/api/v2/accounts/#{gocardless_account_id}/details",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_requisition))

    with {:ok, response} <- Req.get(options) do
      {:ok, response |> Map.get(:body) |> Map.get("account")}
    else
      {:error, error} -> {:error, error}
    end
  end

  def get_account_status(gocardless_account_id) do
    access_token = get_access_token!()

    options =
      [
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_account))

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
    access_token = get_access_token!()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_requisition))

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
    access_token = get_access_token!()

    options =
      [
        url: "https://bankaccountdata.gocardless.com/api/v2/accounts/#{account_id}/transactions",
        auth: {:bearer, access_token},
        receive_timeout: 120_000,
        connect_options: [timeout: 120_000]
      ]
      |> Keyword.merge(mock_data(:bank_data_transactions))
      # disable Req retry in tests to avoid noisy logs when stubs return 429
      |> Keyword.merge(
        if Application.get_env(:firmowid, :bank_data_api_client), do: [retry: false], else: []
      )

    with %Req.Response{status: 200, body: accounts_transaction} <- Req.get!(options) do
      booked_transactions =
        accounts_transaction
        |> Map.get("transactions")
        |> Map.get("booked")

      {:ok, booked_transactions}
    else
      %Req.Response{status: 429} ->
        {:error, :rate_limited}

      error ->
        {:error, error}
    end
  end

  def delete_requisition(requisition_id) do
    access_token = get_access_token!()

    options =
      [
        auth: {:bearer, access_token}
      ]
      |> Keyword.merge(mock_data(:bank_data_requisition))

    with {:ok, requisition} <-
           Req.get(
             options
             |> Keyword.put(
               :url,
               "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}"
             )
           ),
         {:ok, _} <-
           Req.delete(
             options
             |> Keyword.put(
               :url,
               "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}"
             )
           ),
         {:ok, _} <-
           Req.delete(
             options
             |> Keyword.put(
               :url,
               "https://bankaccountdata.gocardless.com/api/v2/agreements/#{requisition.body["agreement"]}"
             )
           ) do
      {:ok, requisition}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp mock_data(key), do: Application.get_env(:firmowid, :bank_data_api_client, [])[key] || []

  defp get_access_token!() do
    cond do
      _mock_data = Application.get_env(:firmowid, :bank_data_api_client) ->
        "fake_access_token"

      token = GenServer.call(TokenManager, :get_access_token) ->
        token

      true ->
        raise "Access token is not set"
    end
  end
end
