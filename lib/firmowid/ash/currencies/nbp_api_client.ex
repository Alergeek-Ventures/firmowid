defmodule Firmowid.Ash.Currencies.NbpApiClient do
  @moduledoc """
  Client for the National Bank of Poland (NBP) API.

  Provides exchange rates for currencies supported by NBP Table A.
  """

  @cache :currencies
  @cache_ttl to_timeout(day: 1)

  @supported_currencies ~w(AUD BRL CAD CHF CLP CNY CZK DKK EUR GBP HKD HUF IDR ILS INR ISK JPY KRW MXN MYR NOK NZD PHP RON SEK SGD THB TRY UAH USD XDR ZAR)

  @doc """
  Returns the list of currency codes supported by NBP Table A.

  These are the only currencies for which exchange rates can be fetched.
  PLN is not included as it's the base currency.
  """
  def supported_currencies, do: @supported_currencies

  @doc """
  Checks if a currency code is supported by NBP.
  """
  def supported_currency?(currency) when is_binary(currency) do
    currency in @supported_currencies
  end

  def supported_currency?(_), do: false

  @doc """
  Fetches the exchange rate for a given currency and date from the NBP API.

  Queries a 20-day range ending at (date - 1 day) to account for weekends/holidays.
  Returns the most recent rate in the range.

  Successful lookups are cached for a day, because invoice previews ask for the
  same rate on every re-render. Requests time out after 5 seconds and are
  retried twice on transient failures; failures are not cached.

  ## Returns

    * `{:ok, %{effective_date: String.t(), rate: float(), table_number: String.t()}}` on success
    * `{:error, reason}` on failure (network error, unexpected response, etc.)
  """
  @spec get_exchange_rate(String.t(), Date.t()) ::
          {:ok, %{effective_date: String.t(), rate: float(), table_number: String.t()}}
          | {:error, term()}
  def get_exchange_rate(currency, date) do
    end_date = date |> clamp_to_today() |> Date.shift(day: -1)

    case Cachex.fetch(@cache, {:nbp_rate, currency, end_date}, fn _key ->
           fetch_rate(currency, end_date)
         end) do
      {status, {:ok, _rate} = result} when status in [:ok, :commit] -> result
      {:ignore, {:error, _reason} = error} -> error
      {:error, reason} -> {:error, {:cache_failed, reason}}
    end
  end

  defp clamp_to_today(date) do
    today = Date.utc_today()
    if Date.before?(date, today), do: date, else: today
  end

  defp fetch_rate(currency, end_date) do
    start_date = Date.shift(end_date, day: -20)

    request_options =
      Keyword.merge(
        [
          url: "https://api.nbp.pl/api/exchangerates/rates/a/#{currency}/#{start_date}/#{end_date}",
          receive_timeout: 5_000,
          retry: :transient,
          max_retries: 2,
          retry_delay: 500
        ],
        Application.get_env(:firmowid, :nbp_api_request_options, [])
      )

    case Req.get(request_options) do
      {:ok, %{status: 200, body: %{"rates" => [_ | _] = rates}}} ->
        %{"effectiveDate" => effective_date, "mid" => rate, "no" => table_number} =
          List.last(rates)

        {:commit, {:ok, %{effective_date: effective_date, rate: rate, table_number: table_number}}, expire: @cache_ttl}

      {:ok, %{status: 404}} ->
        {:ignore, {:error, {:no_rates_found, currency, end_date}}}

      {:ok, %{status: status, body: body}} ->
        {:ignore, {:error, {:unexpected_status, status, body}}}

      {:error, reason} ->
        {:ignore, {:error, {:request_failed, reason}}}
    end
  end
end
