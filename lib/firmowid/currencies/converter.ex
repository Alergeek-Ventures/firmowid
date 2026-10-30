defmodule Firmowid.Currencies.Converter do
  @moduledoc """
  Currency conversion service with multi-layer rate resolution.

  Resolves exchange rates through a layered cache:
  1. In-memory (Cachex) — fastest, populated on first access
  2. Database (Ash ExchangeRate resource) — persistent across restarts
  3. Open Exchange Rates API — external source of truth

  When none of them has rates for the date, conversion raises instead of
  using approximate rates, and the failure is not cached. The `:mock`
  provider, configured outside production, always uses the fixed rates.
  """

  alias Firmowid.Currencies.DatabaseCache

  @doc """
  Given an amount in a given currency and date (for historic rates),
  return the amount in PLN.
  """
  @spec normalize_amount_to_pln(Decimal.t(), String.t(), Date.t()) :: Decimal.t()
  def normalize_amount_to_pln(amount, "PLN", _date), do: amount

  def normalize_amount_to_pln(amount, currency, date) do
    rates = get_rates(date)

    currency
    |> Money.new(amount)
    |> Money.to_currency!("PLN", rates)
    |> Money.to_decimal()
  end

  @spec get_rates(Date.t()) :: map()
  defp get_rates(date) do
    get_rates(date, Application.get_env(:firmowid, __MODULE__)[:rates_provider])
  end

  defp get_rates(_date, :mock), do: mock_rates()

  defp get_rates(date, :api) do
    case Cachex.fetch!(:currencies, date, &fetch_rates/1) do
      {:error, reason} ->
        raise Money.ExchangeRateError, "No exchange rates for #{date}: #{inspect(reason)}"

      rates ->
        rates
    end
  end

  defp fetch_rates(date) do
    case DatabaseCache.get_cache_entry(date) do
      nil -> fetch_oxr_rates(date)
      entry -> {:commit, DatabaseCache.convert_rates_to_decimal(entry.rates)}
    end
  end

  defp fetch_oxr_rates(date) do
    # credo:disable-for-next-line
    case Money.ExchangeRates.historic_rates(date) do
      {:ok, rates} -> {:commit, rates}
      {:error, reason} -> {:ignore, {:error, reason}}
    end
  end

  # Mock rates for the Money library (rates as "units of currency per 1 PLN")
  # The Money library expects rates in the format: how many units of currency X equal 1 unit of base currency
  # With PLN as base (1.0), a rate like EUR: 0.238 means 0.238 EUR = 1 PLN (or 1 EUR = 4.20 PLN)
  # Used only by the `:mock` provider, never as a fallback for the API
  # Source values are NBP Table A mid-rates (PLN per 1 unit of foreign currency), inverted for Money compatibility
  defp mock_rates do
    # NBP rates (PLN per 1 foreign currency unit) - for reference:
    # EUR: 4.2009, USD: 3.5045, GBP: 4.832, CHF: 4.5684, etc.
    # Inverted below for Money library compatibility:
    %{
      PLN: Decimal.new("1.0"),
      AUD: Decimal.new("0.4074838231"),
      BRL: Decimal.new("1.4797277300"),
      CAD: Decimal.new("0.3870419607"),
      CHF: Decimal.new("0.2188916424"),
      CLP: Decimal.new("245.2783418"),
      CNY: Decimal.new("1.9821605550"),
      CZK: Decimal.new("5.7770651646"),
      DKK: Decimal.new("1.7774226627"),
      EUR: Decimal.new("0.2380442286"),
      GBP: Decimal.new("0.2069536424"),
      HKD: Decimal.new("2.2262118491"),
      HUF: Decimal.new("90.497737557"),
      IDR: Decimal.new("4766.4442326"),
      ILS: Decimal.new("0.8827776544"),
      INR: Decimal.new("26.193098644"),
      ISK: Decimal.new("34.564697150"),
      JPY: Decimal.new("43.578024072"),
      KRW: Decimal.new("407.83027407"),
      MXN: Decimal.new("4.8995590397"),
      MYR: Decimal.new("1.1183180496"),
      NOK: Decimal.new("2.7449905024"),
      NZD: Decimal.new("0.4730839675"),
      PHP: Decimal.new("16.750418760"),
      RON: Decimal.new("1.2131553436"),
      SEK: Decimal.new("2.5144580839"),
      SGD: Decimal.new("0.3597381467"),
      THB: Decimal.new("8.8652482270"),
      TRY: Decimal.new("12.391573050"),
      UAH: Decimal.new("12.210012210"),
      USD: Decimal.new("0.2853276150"),
      XDR: Decimal.new("0.2024701356"),
      ZAR: Decimal.new("4.5392646391")
    }
  end
end
