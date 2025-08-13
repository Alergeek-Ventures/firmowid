defmodule Firmowid.Currencies do
  @moduledoc """
  This module is responsible for normalizing amounts between different currencies.
  """

  use Agent

  alias Firmowid.Currencies.DatabaseCache

  def start_link(_opts), do: Agent.start_link(fn -> false end, name: __MODULE__)
  defp rate_limited?, do: Agent.get(__MODULE__, & &1)
  defp set_rate_limiting(value), do: Agent.update(__MODULE__, fn _ -> value end)

  @doc """
  Given an amount in a given currency and date (for historic rates),
  return the amount in PLN.
  """
  @spec normalize_amount_to_pln(Decimal.t(), String.t(), Date.t()) :: Decimal.t()
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
    case Cachex.fetch!(:currencies, date, &get_rates(&1, :database)) do
      :mock -> mock_rates()
      rates -> rates
    end
  end

  defp get_rates(date, :database) do
    case DatabaseCache.get_cache_entry(date) do
      nil -> get_rates(date, :oxr)
      entry -> DatabaseCache.convert_rates_to_decimal(entry.rates)
    end
  end

  defp get_rates(date, :oxr) do
    # returning :mock instead of `mock_rates` to reduce cache size
    if rate_limited?() do
      :mock
    else
      # credo:disable-for-next-line
      case Money.ExchangeRates.historic_rates(date) do
        {:ok, rates} ->
          rates

        {:error, {_, "429"}} ->
          set_rate_limiting(true)
          :mock

        _ ->
          :mock
      end
    end
  end

  defp mock_rates do
    %{
      USD: Decimal.new("1.0"),
      EUR: Decimal.new("0.8554"),
      GBP: Decimal.new("0.7410"),
      CAD: Decimal.new("1.3690"),
      AUD: Decimal.new("1.5216"),
      JPY: Decimal.new("147.0598"),
      CHF: Decimal.new("0.7969"),
      CNY: Decimal.new("7.1686"),
      SEK: Decimal.new("9.547"),
      NOK: Decimal.new("10.50"),
      DKK: Decimal.new("6.39"),
      CZK: Decimal.new("21.11"),
      PLN: Decimal.new("3.645"),
      HUF: Decimal.new("342.4"),
      INR: Decimal.new("83.50"),
      BRL: Decimal.new("5.45"),
      MXN: Decimal.new("18.30"),
      ZAR: Decimal.new("18.00")
    }
  end
end
