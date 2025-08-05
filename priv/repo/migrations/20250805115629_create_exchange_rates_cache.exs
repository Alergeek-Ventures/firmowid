defmodule Firmowid.Repo.Migrations.CreateExchangeRatesCache do
  use Ecto.Migration

  def change do
    create table(:exchange_rates_cache, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # NULL for latest, specific date for historic
      add :cache_date, :date
      # Exchange rates map from API
      add :rates, :jsonb, null: false
      add :retrieved_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false, default: fragment("NOW() + INTERVAL '30 days'")

      timestamps(type: :utc_datetime)
    end

    create unique_index(:exchange_rates_cache, [:cache_date])
    create index(:exchange_rates_cache, [:expires_at])
  end
end
