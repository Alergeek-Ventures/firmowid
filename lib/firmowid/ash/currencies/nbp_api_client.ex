defmodule Firmowid.Ash.Currencies.NbpApiClient do
  @moduledoc """
  Client for the National Bank of Poland (NBP) API.

  Provides exchange rates for currencies supported by NBP Table A.
  """

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

  ## Returns

    * `{:ok, %{effective_date: String.t(), rate: float(), table_number: String.t()}}` on success
    * `{:error, reason}` on failure (network error, unexpected response, etc.)
  """
  @spec get_exchange_rate(String.t(), Date.t()) ::
          {:ok, %{effective_date: String.t(), rate: float(), table_number: String.t()}}
          | {:error, term()}
  def get_exchange_rate(currency, date) do
    today = Date.utc_today()

    clamped_date =
      case Date.compare(date, today) do
        :lt -> date
        _ -> today
      end

    date_max_till_yesterday = Date.shift(clamped_date, Duration.new!(day: -1))

    end_date_str = Date.to_iso8601(date_max_till_yesterday)

    start_date_str =
      date_max_till_yesterday |> Date.shift(Duration.new!(day: -20)) |> Date.to_iso8601()

    url =
      "https://api.nbp.pl/api/exchangerates/rates/a/#{currency}/#{start_date_str}/#{end_date_str}"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"rates" => [_ | _] = rates}}} ->
        %{"effectiveDate" => effective_date, "mid" => rate, "no" => table_number} =
          List.last(rates)

        {:ok, %{effective_date: effective_date, rate: rate, table_number: table_number}}

      {:ok, %{status: 404}} ->
        {:error, {:no_rates_found, currency, date}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
