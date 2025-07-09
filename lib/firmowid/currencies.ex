defmodule Firmowid.Currencies do
  @moduledoc """
  This module is responsible for normalizing amounts between different currencies.
  """

  alias Money
  alias Decimal

  @doc """
  Given an amount in a given currency and date (for historic rates),
  return the amount in PLN.
  """
  @spec normalize_amount_to_pln(Decimal.t(), String.t(), Date.t()) :: Decimal.t()
  def normalize_amount_to_pln(amount, currency, date) do
    rates = get_rates(date)

    {:ok, amount} =
      Money.new(
        currency,
        amount
      )
      |> Money.to_currency(
        "PLN",
        rates
      )

    amount |> Money.to_decimal()
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
      EUR: Decimal.new("0.92"),
      PLN: Decimal.new("4.05"),
      USD: Decimal.new("1.0")
    }
  end
end
