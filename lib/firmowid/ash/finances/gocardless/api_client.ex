defmodule Firmowid.Ash.Finances.GoCardless.ApiClient do
  @moduledoc """
  HTTP client for the GoCardless Bank Account Data API (v2).

  All public functions return `{:ok, result}` or `{:error, reason}` where
  reason is one of the atoms defined in `handle_response/1`.
  """

  alias Firmowid.Ash.Finances.GoCardless.TokenManager

  require Logger

  @base_url "https://bankaccountdata.gocardless.com/api/v2"

  @doc """
  Lists available banking institutions for the given country code.
  """
  @spec get_available_institutions_for_country(String.t()) ::
          {:ok, list(map())} | {:error, term()}
  def get_available_institutions_for_country(country) do
    options =
      Keyword.merge(
        [
          url: "#{@base_url}/institutions/?country=#{country}",
          auth: {:bearer, get_access_token!()}
        ],
        mock_data(:bank_data_institutions)
      )

    options
    |> Req.get()
    |> handle_response()
  end

  @doc """
  Fetches a single requisition by its GoCardless ID.
  """
  @spec get_requisition(String.t()) :: {:ok, map()} | {:error, term()}
  def get_requisition(requisition_id) do
    options =
      Keyword.merge(
        [
          url: "#{@base_url}/requisitions/#{requisition_id}",
          auth: {:bearer, get_access_token!()}
        ],
        mock_data(:bank_data_requisition)
      )

    options
    |> Req.get()
    |> handle_response()
  end

  @doc """
  Creates an end-user agreement and a requisition for the given institution.
  Returns the full requisition body on success.
  """
  @spec create_requisition(String.t(), integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def create_requisition(institution_id, max_transaction_days, redirect_url) do
    access_token = get_access_token!()

    agreement_opts =
      Keyword.merge(
        [url: "#{@base_url}/agreements/enduser/", auth: {:bearer, access_token}],
        mock_data(:bank_data_requisition)
      )

    requisition_opts =
      Keyword.merge(
        [url: "#{@base_url}/requisitions/", auth: {:bearer, access_token}],
        mock_data(:bank_data_requisition)
      )

    with {:ok, %{"id" => agreement_id}} <-
           agreement_opts
           |> Keyword.put(:json, %{
             institution_id: institution_id,
             max_historical_days: min(max_transaction_days, 90),
             access_valid_for_days: 90,
             access_scope: ["balances", "details", "transactions"]
           })
           |> Req.post()
           |> handle_response() do
      requisition_opts
      |> Keyword.put(:json, %{
        redirect: redirect_url,
        institution_id: institution_id,
        agreement: agreement_id,
        user_language: "PL"
      })
      |> Req.post()
      |> handle_response()
    end
  end

  @doc """
  Fetches institution details by GoCardless institution ID.
  """
  @spec get_institution(String.t()) :: {:ok, map()} | {:error, term()}
  def get_institution(go_cardless_institution_id) do
    options =
      Keyword.merge(
        [
          url: "#{@base_url}/institutions/#{go_cardless_institution_id}",
          auth: {:bearer, get_access_token!()}
        ],
        mock_data(:bank_data_institution)
      )

    options
    |> Req.get()
    |> handle_response()
  end

  @doc """
  Fetches account details (name, IBAN, etc.) for a GoCardless account.
  Returns the nested `"account"` map from the response.
  """
  @spec get_account_details(String.t()) :: {:ok, map()} | {:error, term()}
  def get_account_details(gocardless_account_id) do
    options =
      Keyword.merge(
        [
          url: "#{@base_url}/accounts/#{gocardless_account_id}/details",
          auth: {:bearer, get_access_token!()}
        ],
        mock_data(:bank_data_requisition)
      )

    case options |> Req.get() |> handle_response() do
      {:ok, %{"account" => account}} -> {:ok, account}
      {:ok, body} -> {:ok, body}
      error -> error
    end
  end

  @doc """
  Fetches account metadata (status, institution_id, etc.) for a GoCardless account.
  """
  @spec get_account_status(String.t()) :: {:ok, map()} | {:error, term()}
  def get_account_status(gocardless_account_id) do
    options =
      Keyword.merge(
        [
          url: "#{@base_url}/accounts/#{gocardless_account_id}",
          auth: {:bearer, get_access_token!()}
        ],
        mock_data(:bank_data_account)
      )

    options
    |> Req.get()
    |> handle_response()
  end

  @doc """
  Fetches all account details for accounts linked to a requisition.
  Enriches each account with status, details, and institution info.
  """
  @spec get_accounts_for_requisition(String.t()) :: {:ok, list(map())} | {:error, term()}
  def get_accounts_for_requisition(requisition_id) do
    with {:ok, requisition_body} <- get_requisition(requisition_id) do
      results =
        requisition_body
        |> Map.get("accounts", [])
        |> Enum.map(&fetch_enriched_account/1)

      case Enum.find(results, &match?({:error, _}, &1)) do
        {:error, _} = error -> error
        nil -> {:ok, Enum.map(results, fn {:ok, account} -> account end)}
      end
    end
  end

  defp fetch_enriched_account(account_id) do
    with {:ok, account_response} <- get_account_status(account_id),
         {:ok, account_details} <- get_account_details(account_id),
         {:ok, institution} <- get_institution(account_response["institution_id"]) do
      {:ok,
       account_response
       |> Map.merge(account_details)
       |> Map.put("institution", institution)}
    end
  end

  @doc """
  Fetches booked transactions for a GoCardless account.
  Uses extended timeouts since bank APIs can be slow.
  """
  @spec get_booked_transactions_for_account(String.t()) ::
          {:ok, list(map())} | {:error, term()}
  def get_booked_transactions_for_account(account_id) do
    options =
      Keyword.merge(
        [
          url: "#{@base_url}/accounts/#{account_id}/transactions",
          auth: {:bearer, get_access_token!()},
          receive_timeout: 120_000,
          connect_options: [timeout: 120_000]
        ],
        mock_data(:bank_data_transactions)
      )

    case options |> Req.get() |> handle_response() do
      {:ok, %{"transactions" => %{"booked" => booked}}} ->
        {:ok, booked}

      {:ok, _unexpected_body} ->
        {:error, :unexpected_response}

      error ->
        error
    end
  end

  @doc """
  Deletes a requisition and its associated agreement from GoCardless.
  First fetches the requisition to get the agreement ID, then deletes both.
  """
  @spec delete_requisition(String.t()) :: {:ok, map()} | {:error, term()}
  def delete_requisition(requisition_id) do
    access_token = get_access_token!()
    options = Keyword.merge([auth: {:bearer, access_token}], mock_data(:bank_data_requisition))

    with {:ok, requisition_body} <-
           options
           |> Keyword.put(:url, "#{@base_url}/requisitions/#{requisition_id}")
           |> Req.get()
           |> handle_response(),
         {:ok, _} <-
           options
           |> Keyword.put(:url, "#{@base_url}/requisitions/#{requisition_id}")
           |> Req.delete()
           |> handle_response(),
         {:ok, _} <-
           options
           |> Keyword.put(:url, "#{@base_url}/agreements/#{requisition_body["agreement"]}")
           |> Req.delete()
           |> handle_response() do
      {:ok, requisition_body}
    end
  end

  @doc """
  Wraps an API call with a single token-refresh retry on `:unauthorized`.

  If the wrapped function returns `{:error, :unauthorized}`, refreshes the
  access token via `TokenManager.refresh_now/0` and retries once. All other
  results (including `{:error, :expired_eua}`) pass through unchanged.

  ## Example

      ApiClient.with_token_refresh(fn ->
        ApiClient.get_booked_transactions_for_account(account_id)
      end)
  """
  @spec with_token_refresh((-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def with_token_refresh(fun) when is_function(fun, 0) do
    case fun.() do
      {:error, :unauthorized} ->
        case TokenManager.refresh_now() do
          nil -> {:error, :token_refresh_failed}
          _token -> fun.()
        end

      other ->
        other
    end
  end

  # --- Shared response handler ---

  # Maps HTTP responses to consistent {:ok, body} | {:error, reason} tuples.
  # Covers all status codes from the GoCardless Bank Account Data API OpenAPI spec.
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}) ::
          {:ok, term()} | {:error, term()}
  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in [200, 201] do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: 400, body: body}}) do
    Logger.warning("GoCardless API bad request: #{inspect(body)}")
    {:error, :bad_request}
  end

  defp handle_response({:ok, %Req.Response{status: 401, body: %{"summary" => summary}}}) when is_binary(summary) do
    if String.contains?(summary, "End User Agreement (EUA)") and
         String.contains?(summary, "has expired") do
      {:error, :expired_eua}
    else
      {:error, :unauthorized}
    end
  end

  defp handle_response({:ok, %Req.Response{status: 401}}) do
    {:error, :unauthorized}
  end

  defp handle_response({:ok, %Req.Response{status: 403, body: body}}) do
    Logger.warning("GoCardless API forbidden: #{inspect(body)}")
    {:error, :forbidden}
  end

  defp handle_response({:ok, %Req.Response{status: 404}}) do
    {:error, :not_found}
  end

  defp handle_response({:ok, %Req.Response{status: 409, body: body}}) do
    Logger.warning("GoCardless API conflict (account suspended/error state): #{inspect(body)}")
    {:error, :conflict}
  end

  defp handle_response({:ok, %Req.Response{status: 429}}) do
    {:error, :rate_limited}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status >= 500 and status < 600 do
    Logger.warning("GoCardless API server error #{status}: #{inspect(body)}")
    {:error, :server_error}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    Logger.warning("GoCardless API unexpected status #{status}: #{inspect(body)}")
    {:error, {:unexpected_status, status}}
  end

  defp handle_response({:error, %Req.TransportError{} = error}) do
    Logger.warning("GoCardless API transport error: #{inspect(error)}")
    {:error, :server_error}
  end

  defp handle_response({:error, reason}) do
    Logger.warning("GoCardless API request failed: #{inspect(reason)}")
    {:error, {:request_failed, reason}}
  end

  # --- Helpers ---

  defp mock_data(key), do: Application.get_env(:firmowid, :bank_data_api_client, [])[key] || []

  defp get_access_token! do
    cond do
      Application.get_env(:firmowid, :bank_data_api_client) ->
        "fake_access_token"

      token = TokenManager.get_access_token() ->
        token

      true ->
        raise "Access token is not set"
    end
  end
end
