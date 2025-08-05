defmodule Firmowid.ExchangeRates.CacheEntry do
  use Firmowid.Schema

  import Ecto.Changeset

  schema "exchange_rates_cache" do
    field :cache_date, :date
    field :rates, :map
    field :retrieved_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(cache_entry, attrs) do
    cache_entry
    |> cast(attrs, [:cache_date, :rates, :retrieved_at, :expires_at])
    |> validate_required([:rates, :retrieved_at, :expires_at])
  end
end
