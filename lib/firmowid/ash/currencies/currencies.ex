defmodule Firmowid.Ash.Currencies do
  @moduledoc """
  Ash domain for exchange rate caching.

  Provides database-backed cache for historic exchange rates used by the
  Money library for currency conversions. Cleanup of expired entries is
  handled by an AshOban trigger on the ExchangeRate resource.
  """

  use Ash.Domain

  resources do
    resource Firmowid.Ash.Currencies.ExchangeRate do
      define :get_exchange_rate_by_date, action: :get_by_date, args: [:cache_date]
      define :upsert_exchange_rate, action: :upsert
    end
  end
end
