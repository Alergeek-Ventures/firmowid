defmodule Firmowid.Currencies do
  @moduledoc """
  This module is responsible for normalizing amounts between different currencies.
  """

  @doc """
  Given an amount in a given currency and date (for historic rates),
  return the amount in PLN.
  """
  @spec normalize_amount_to_pln(Decimal.t(), String.t(), Date.t()) :: Decimal.t()
  def normalize_amount_to_pln(amount, currency, date) do
    rates = get_rates(date)

    {:ok, amount} =
      currency
      |> Money.new(amount)
      |> Money.to_currency(
        "PLN",
        rates
      )

    Money.to_decimal(amount)
  end

  @spec get_rates(Date.t()) :: map()
  defp get_rates(date) do
    case Application.get_env(:firmowid, __MODULE__)[:rates_provider] do
      :mock ->
        mock_rates()

      _ ->
        case get_rates_from_api(date) do
          {:ok, rates} -> rates
          _ -> mock_rates()
        end
    end
  end

  defp get_rates_from_api(date) do
    Money.ExchangeRates.historic_rates(date)
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
