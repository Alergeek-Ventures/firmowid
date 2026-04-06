defmodule Firmowid.Ash.Currencies.ExchangeRate do
  @moduledoc """
  Cached exchange rates for a specific date.

  Stores historic rates from Open Exchange Rates (OXR) in the database
  as a JSON map. Used as the persistence layer for the Money library's
  exchange rate cache.
  """

  use Ash.Resource,
    domain: Firmowid.Ash.Currencies,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "exchange_rates_cache"
    repo Firmowid.Repo
    migrate? false
  end

  oban do
    triggers do
      trigger :cleanup_expired do
        action :cleanup_expired
        read_action :read_expired
        scheduler_cron "0 14 * * *"
        max_attempts 3
        queue :default

        worker_module_name Firmowid.Ash.Currencies.ExchangeRate.Worker.CleanupExpired
        scheduler_module_name Firmowid.Ash.Currencies.ExchangeRate.Scheduler.CleanupExpired
      end
    end
  end

  actions do
    defaults [:read]

    read :read_expired do
      description "Reads expired cache entries for AshOban cleanup trigger."
      filter expr(expires_at < now())
      pagination keyset?: true
    end

    read :get_by_date do
      description "Fetches a single cache entry by date."
      argument :cache_date, :date, allow_nil?: false
      get? true
      filter expr(cache_date == ^arg(:cache_date))
    end

    create :upsert do
      description "Creates or updates a cache entry for a given date."
      accept [:cache_date, :rates, :retrieved_at, :expires_at]
      upsert? true
      upsert_identity :unique_cache_date
      upsert_fields {:replace_all_except, [:id, :inserted_at]}
    end

    destroy :cleanup_expired do
      description "AshOban trigger action — destroys an expired cache entry."
    end
  end

  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:upsert) do
      forbid_if always()
    end

    policy action(:cleanup_expired) do
      forbid_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :cache_date, :date, public?: true
    attribute :rates, :map, allow_nil?: false, public?: true
    attribute :retrieved_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime, allow_nil?: false, public?: true

    Resource.firmowid_timestamps()
  end

  identities do
    identity :unique_cache_date, [:cache_date]
  end
end
