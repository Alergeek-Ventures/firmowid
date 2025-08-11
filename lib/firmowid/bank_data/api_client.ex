defmodule Firmowid.BankData.ApiClient do
  @moduledoc false
  alias Firmowid.BankData.TokenManager

  def get_available_institutions_for_country(country) do
    access_token = get_access_token!()

    options =
      Keyword.merge(
        [
          url: "https://bankaccountdata.gocardless.com/api/v2/institutions/?country=#{country}",
          auth: {:bearer, access_token}
        ],
        mock_data(:bank_data_institutions)
      )

    case Req.get(options) do
      {:ok, response} -> Map.get(response, :body)
      {:error, error} -> {:error, error}
    end
  end

  def get_requisition(requisition_id) do
    access_token = get_access_token!()

    options =
      Keyword.merge(
        [
          url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
          auth: {:bearer, access_token}
        ],
        mock_data(:bank_data_requisition)
      )

    case Req.get(options) do
      {:ok, response} -> Map.get(response, :body)
      {:error, error} -> {:error, error}
    end
  end

  def create_requisition(institution_id, max_transaction_days, redirect_url) do
    access_token = get_access_token!()

    agreement_opts =
      Keyword.merge(
        [url: "https://bankaccountdata.gocardless.com/api/v2/agreements/enduser/", auth: {:bearer, access_token}],
        mock_data(:bank_data_requisition)
      )

    requisition_opts =
      Keyword.merge(
        [url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/", auth: {:bearer, access_token}],
        mock_data(:bank_data_requisition)
      )

    with %{body: %{"id" => agreement_id}} <-
           Req.post!(
             Keyword.put(agreement_opts, :json, %{
               institution_id: institution_id,
               max_historical_days: min(max_transaction_days, 90),
               access_valid_for_days: 90,
               access_scope: ["balances", "details", "transactions"]
             })
           ),
         %{body: requisition_body, status: 201} <-
           Req.post!(
             Keyword.put(requisition_opts, :json, %{
               redirect: redirect_url,
               institution_id: institution_id,
               agreement: agreement_id,
               user_language: "PL"
             })
           ) do
      requisition_body
    end
  end

  def get_institution(go_cardless_institution_id) do
    access_token = get_access_token!()

    options =
      Keyword.merge(
        [
          url: "https://bankaccountdata.gocardless.com/api/v2/institutions/#{go_cardless_institution_id}",
          auth: {:bearer, access_token}
        ],
        mock_data(:bank_data_institution)
      )

    case Req.get(options) do
      {:ok, response} -> {:ok, Map.get(response, :body)}
      {:error, error} -> {:error, error}
    end
  end

  def get_account_details(gocardless_account_id) do
    access_token = get_access_token!()

    options =
      Keyword.merge(
        [
          url: "https://bankaccountdata.gocardless.com/api/v2/accounts/#{gocardless_account_id}/details",
          auth: {:bearer, access_token}
        ],
        mock_data(:bank_data_requisition)
      )

    case Req.get(options) do
      {:ok, response} -> {:ok, response |> Map.get(:body) |> Map.get("account")}
      {:error, error} -> {:error, error}
    end
  end

  def get_account_status(gocardless_account_id) do
    access_token = get_access_token!()

    options = Keyword.merge([auth: {:bearer, access_token}], mock_data(:bank_data_account))

    case options
         |> Keyword.put(
           :url,
           "https://bankaccountdata.gocardless.com/api/v2/accounts/#{gocardless_account_id}"
         )
         |> Req.get() do
      {:ok, account_response} -> {:ok, Map.get(account_response, :body)}
      {:error, error} -> {:error, error}
    end
  end

  def get_accounts_for_requisition(requisition_id) do
    access_token = get_access_token!()

    options =
      Keyword.merge(
        [
          url: "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}",
          auth: {:bearer, access_token}
        ],
        mock_data(:bank_data_requisition)
      )

    with {:ok, response} <- Req.get(options) do
      accounts = Map.get(response.body, "accounts", [])

      Enum.map(accounts, fn account ->
        with {:ok, account_response} <-
               get_account_status(account),
             {:ok, account_details} <-
               get_account_details(account) do
          {:ok, institution} = get_institution(account_response["institution_id"])

          account_response
          |> Map.merge(account_details)
          |> Map.put(
            "institution",
            institution
          )
        end
      end)
    end
  end

  def get_booked_transactions_for_account(account_id) do
    access_token = get_access_token!()

    options =
      Keyword.merge(
        [
          url: "https://bankaccountdata.gocardless.com/api/v2/accounts/#{account_id}/transactions",
          auth: {:bearer, access_token},
          receive_timeout: 120_000,
          connect_options: [timeout: 120_000]
        ],
        mock_data(:bank_data_transactions)
      )

    case Req.get!(options) do
      %Req.Response{status: 200, body: accounts_transaction} ->
        booked_transactions =
          accounts_transaction
          |> Map.get("transactions")
          |> Map.get("booked")

        {:ok, booked_transactions}

      %Req.Response{status: 429} ->
        {:error, :rate_limited}

      error ->
        {:error, error}
    end
  end

  def delete_requisition(requisition_id) do
    access_token = get_access_token!()

    options = Keyword.merge([auth: {:bearer, access_token}], mock_data(:bank_data_requisition))

    with {:ok, requisition} <-
           options
           |> Keyword.put(
             :url,
             "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}"
           )
           |> Req.get(),
         {:ok, _} <-
           options
           |> Keyword.put(
             :url,
             "https://bankaccountdata.gocardless.com/api/v2/requisitions/#{requisition_id}"
           )
           |> Req.delete(),
         {:ok, _} <-
           options
           |> Keyword.put(
             :url,
             "https://bankaccountdata.gocardless.com/api/v2/agreements/#{requisition.body["agreement"]}"
           )
           |> Req.delete() do
      {:ok, requisition}
    end
  end

  defp mock_data(key), do: Application.get_env(:firmowid, :bank_data_api_client, [])[key] || []

  defp get_access_token! do
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
