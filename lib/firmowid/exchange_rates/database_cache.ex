defmodule Firmowid.ExchangeRates.DatabaseCache do
  @behaviour Money.ExchangeRates.Cache

  alias Firmowid.Repo
  alias Firmowid.ExchangeRates.CacheEntry
  import Ecto.Query

  @impl true
  def init do
    # No initialization needed for database cache
    :ok
  end

  @impl true
  def latest_rates do
    # We don't cache latest rates in this implementation
    error_message = "Latest rates caching not implemented"
    {:error, {Money.ExchangeRateError.exception(message: error_message), error_message}}
  end

  @impl true
  def historic_rates(date) do
    case get_cache_entry(date) do
      nil ->
        error_message = "No rates available for #{date}"
        {:error, {Money.ExchangeRateError.exception(message: error_message), error_message}}

      entry ->
        {:ok, convert_rates_to_decimal(entry.rates)}
    end
  end

  @impl true
  def store_latest_rates(_rates, _retrieved_at) do
    # We don't cache latest rates in this implementation
    :ok
  end

  @impl true
  def store_historic_rates(rates, date, retrieved_at \\ DateTime.utc_now()) do
    attrs = %{
      cache_date: date,
      rates: rates,
      retrieved_at: retrieved_at,
      expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
    }

    upsert_cache_entry(attrs)
    :ok
  end

  @impl true
  def terminate do
    # No cleanup needed
    :ok
  end

  defp get_cache_entry(cache_date) do
    query =
      from c in CacheEntry,
        where: c.cache_date == ^cache_date

    query
    |> Repo.one(skip_organization_id: true)
  end

  defp upsert_cache_entry(attrs) do
    %CacheEntry{}
    |> CacheEntry.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:cache_date],
      skip_organization_id: true
    )
  end

  defp convert_rates_to_decimal(rates) do
    Map.new(rates, fn {currency, value} ->
      {currency, to_decimal(value)}
    end)
  end

  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
end
