defmodule Firmowid.Ash.Currencies.DatabaseCache do
  @moduledoc """
  Database-backed cache implementing the `Money.ExchangeRates.Cache` behaviour.

  Uses the `Firmowid.Ash.Currencies` domain to persist and retrieve exchange
  rates via the `ExchangeRate` Ash resource. Cleanup of expired entries is
  handled by AshOban on the resource, not by this module.
  """

  @behaviour Money.ExchangeRates.Cache

  alias Firmowid.Ash.Currencies
  alias Firmowid.Ash.SystemActor

  @cache_actor %SystemActor{org_id: nil, role: :exchange_rate_cache}
  @cache_opts [actor: @cache_actor]

  @impl true
  def init(_name), do: :ok

  @impl true
  def latest_rates(_cache) do
    error_message = "Latest rates caching not implemented"
    {:error, {Money.ExchangeRateError.exception(message: error_message), error_message}}
  end

  @impl true
  def historic_rates(_cache, date) do
    case get_cache_entry(date) do
      nil ->
        error_message = "No rates available for #{date}"
        {:error, {Money.ExchangeRateError.exception(message: error_message), error_message}}

      entry ->
        {:ok, convert_rates_to_decimal(entry.rates)}
    end
  end

  @impl true
  def store_latest_rates(_cache, _rates, _retrieved_at), do: :ok

  @impl true
  def store_historic_rates(_cache, rates, date) do
    attrs = %{
      cache_date: date,
      rates: rates,
      retrieved_at: DateTime.utc_now(),
      expires_at: DateTime.shift(DateTime.utc_now(), day: 30)
    }

    Currencies.upsert_exchange_rate!(attrs, @cache_opts)
    :ok
  end

  @impl true
  def terminate(_cache), do: :ok

  @spec get_cache_entry(Date.t()) :: struct() | nil
  def get_cache_entry(cache_date) do
    case Currencies.get_exchange_rate_by_date(cache_date) do
      {:ok, entry} -> entry
      {:error, _} -> nil
    end
  end

  @spec convert_rates_to_decimal(map()) :: map()
  def convert_rates_to_decimal(rates) do
    Map.new(rates, fn {currency, value} ->
      {currency, to_decimal(value)}
    end)
  end

  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
end
