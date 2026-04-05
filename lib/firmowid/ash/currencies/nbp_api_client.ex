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

  def get_exchange_rate(currency, date) do
    today = Date.utc_today()

    case_result =
      case Date.compare(date, today) do
        :lt -> date
        :eq -> today
        :gt -> today
      end

    date_max_till_yesterday = Date.shift(case_result, Duration.new!(day: -1))

    end_date_str = Date.to_iso8601(date_max_till_yesterday)

    start_date_str =
      date_max_till_yesterday |> Date.shift(Duration.new!(day: -20)) |> Date.to_iso8601()

    %{
      body: %{
        "rates" => rates
      }
    } =
      Req.get!("https://api.nbp.pl/api/exchangerates/rates/a/#{currency}/#{start_date_str}/#{end_date_str}")

    %{"effectiveDate" => effective_date, "mid" => rate, "no" => table_number} = Enum.at(rates, -1)

    %{effective_date: effective_date, rate: rate, table_number: table_number}
  end
end
