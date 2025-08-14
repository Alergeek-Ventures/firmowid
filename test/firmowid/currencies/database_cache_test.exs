defmodule Firmowid.Currencies.DatabaseCacheTest do
  use Firmowid.DataCase

  alias Firmowid.Currencies.CacheEntry
  alias Firmowid.Currencies.CleanupWorker
  alias Firmowid.Currencies.DatabaseCache

  setup_all do
    # Configure to use API rates provider instead of mock
    original_config = Application.get_env(:firmowid, Firmowid.Currencies)
    Application.put_env(:firmowid, Firmowid.Currencies, rates_provider: :api)

    on_exit(fn ->
      # Restore original config
      Application.put_env(:firmowid, Firmowid.Currencies, original_config)
    end)
  end

  describe "database cache behavior" do
    test "stores and retrieves historic rates" do
      # Test storing rates for a specific date
      date = ~D[2024-01-15]

      rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("0.85"),
        "GBP" => Decimal.new("0.73"),
        "PLN" => Decimal.new("4.05")
      }

      # Store rates in cache
      assert :ok = DatabaseCache.store_historic_rates(rates, date)

      # Verify cache was populated
      assert Repo.aggregate(CacheEntry, :count, skip_organization_id: true) == 1

      # Retrieve rates from cache
      assert {:ok, fetched_rates} = DatabaseCache.historic_rates(date)

      # Verify we got the cached rates with proper decimal conversion
      assert fetched_rates["EUR"] == Decimal.new("0.85")
      assert fetched_rates["GBP"] == Decimal.new("0.73")
      assert fetched_rates["PLN"] == Decimal.new("4.05")
    end
  end

  describe "end-to-end Money integration" do
    test "Money.ExchangeRates uses database cache for historic rates" do
      # Seed the database with exchange rates
      date = ~D[2024-01-15]

      seeded_rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("0.85"),
        "GBP" => Decimal.new("0.73"),
        "PLN" => Decimal.new("4.05")
      }

      # Store rates in cache
      DatabaseCache.store_historic_rates(seeded_rates, date)

      # Verify cache was populated
      assert Repo.aggregate(CacheEntry, :count, skip_organization_id: true) == 1

      # Use Money.ExchangeRates to fetch rates - should hit cache
      # credo:disable-for-next-line
      {:ok, rates} = Money.ExchangeRates.historic_rates(date)

      # Verify we got the cached rates
      assert rates["EUR"] == Decimal.new("0.85")
      assert rates["GBP"] == Decimal.new("0.73")
      assert rates["PLN"] == Decimal.new("4.05")

      # Verify cache was hit (still only 1 entry)
      assert Repo.aggregate(CacheEntry, :count, skip_organization_id: true) == 1
    end

    test "Money.to_currency uses cached rates for conversion" do
      # Seed the database with exchange rates
      date = ~D[2024-01-15]

      seeded_rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("2.0"),
        "PLN" => Decimal.new("2.0")
      }

      DatabaseCache.store_historic_rates(seeded_rates, date)

      # Get rates for the date
      # credo:disable-for-next-line
      {:ok, rates} = Money.ExchangeRates.historic_rates(date)

      # Create money in EUR and convert to USD using cached rates
      eur_money = Money.new("EUR", Decimal.new("100"))
      {:ok, usd_money} = Money.to_currency(eur_money, "USD", rates)

      assert Money.to_decimal(usd_money) == Decimal.new("50.0")
    end

    test "Firmowid.Currencies.normalize_amount_to_pln uses cached rates" do
      # Seed the database
      date = ~D[2024-01-15]

      # naively simple - only important thing is that it's different to the
      # mock rates
      seeded_rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("1.0"),
        "PLN" => Decimal.new("2.0")
      }

      DatabaseCache.store_historic_rates(seeded_rates, date)

      # Use the Currencies module which should use cached rates
      amount_eur = Decimal.new("100")
      amount_pln = Firmowid.Currencies.normalize_amount_to_pln(amount_eur, "EUR", date)

      expected_pln = Decimal.new("200")

      assert amount_pln == expected_pln

      # Verify cache was hit (still only 1 entry)
      assert Repo.aggregate(CacheEntry, :count, skip_organization_id: true) == 1
    end
  end

  describe "historic_rates/1" do
    test "returns error when no rates for date" do
      date = ~D[2024-01-15]
      assert {:error, {%Money.ExchangeRateError{}, _}} = DatabaseCache.historic_rates(date)
    end

    test "returns rates when cached for date" do
      date = ~D[2024-01-15]
      rates = %{"EUR" => Decimal.new("0.85"), "GBP" => Decimal.new("0.73")}
      DatabaseCache.store_historic_rates(rates, date)

      assert {:ok, fetched_rates} = DatabaseCache.historic_rates(date)
      assert fetched_rates["EUR"] == Decimal.new("0.85")
      assert fetched_rates["GBP"] == Decimal.new("0.73")
    end

    test "stores different rates for different dates" do
      date1 = ~D[2024-01-15]
      date2 = ~D[2024-01-16]
      rates1 = %{"EUR" => Decimal.new("0.85")}
      rates2 = %{"EUR" => Decimal.new("0.90")}

      DatabaseCache.store_historic_rates(rates1, date1)
      DatabaseCache.store_historic_rates(rates2, date2)

      assert {:ok, fetched_rates1} = DatabaseCache.historic_rates(date1)
      assert fetched_rates1["EUR"] == Decimal.new("0.85")

      assert {:ok, fetched_rates2} = DatabaseCache.historic_rates(date2)
      assert fetched_rates2["EUR"] == Decimal.new("0.90")
    end
  end

  describe "cleanup worker" do
    test "removes expired entries" do
      # Create expired entry
      expired_attrs = %{
        cache_date: ~D[2023-01-01],
        rates: %{"EUR" => Decimal.new("0.85")},
        retrieved_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
      }

      {:ok, _} =
        %CacheEntry{}
        |> CacheEntry.changeset(expired_attrs)
        |> Repo.insert(skip_organization_id: true)

      # Create non-expired entry
      current_attrs = %{
        cache_date: ~D[2024-01-01],
        rates: %{"EUR" => Decimal.new("0.90")},
        retrieved_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), 30, :day)
      }

      {:ok, _} =
        %CacheEntry{}
        |> CacheEntry.changeset(current_attrs)
        |> Repo.insert(skip_organization_id: true)

      assert Repo.aggregate(CacheEntry, :count, skip_organization_id: true) == 2

      assert {:ok, %{deleted_count: 1}} =
               perform_job(CleanupWorker, %{})

      assert Repo.aggregate(CacheEntry, :count, skip_organization_id: true) == 1
    end
  end
end
