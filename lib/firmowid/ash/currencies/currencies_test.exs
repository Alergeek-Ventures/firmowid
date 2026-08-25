defmodule Firmowid.Ash.Currencies.CurrenciesTest do
  @moduledoc false
  use Firmowid.DataCase

  alias Firmowid.Ash.Currencies.Converter
  alias Firmowid.Ash.Currencies.DatabaseCache
  alias Firmowid.Ash.Currencies.ExchangeRate

  # authorize?: false bypasses policies, actor: %{} satisfies require_actor? true
  # on domains like Currencies.
  @bridge_opts [authorize?: false, actor: %{}]

  setup_all do
    # Configure to use API rates provider instead of mock
    original_config = Application.get_env(:firmowid, Converter)
    Application.put_env(:firmowid, Converter, rates_provider: :api)

    on_exit(fn ->
      Application.put_env(:firmowid, Converter, original_config)
    end)
  end

  setup do
    # Clear Cachex between tests to avoid stale in-memory cache
    Cachex.clear!(:currencies)
    :ok
  end

  describe "database cache behavior" do
    test "stores and retrieves historic rates" do
      date = ~D[2024-01-15]

      rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("0.85"),
        "GBP" => Decimal.new("0.73"),
        "PLN" => Decimal.new("4.05")
      }

      assert :ok = DatabaseCache.store_historic_rates(nil, rates, date)

      assert {:ok, 1} = Ash.count(ExchangeRate, @bridge_opts)

      assert {:ok, fetched_rates} = DatabaseCache.historic_rates(nil, date)

      assert fetched_rates["EUR"] == Decimal.new("0.85")
      assert fetched_rates["GBP"] == Decimal.new("0.73")
      assert fetched_rates["PLN"] == Decimal.new("4.05")
    end
  end

  describe "end-to-end Money integration" do
    test "Money.ExchangeRates uses database cache for historic rates" do
      date = ~D[2024-01-15]

      seeded_rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("0.85"),
        "GBP" => Decimal.new("0.73"),
        "PLN" => Decimal.new("4.05")
      }

      DatabaseCache.store_historic_rates(nil, seeded_rates, date)

      assert {:ok, 1} = Ash.count(ExchangeRate, @bridge_opts)

      # credo:disable-for-next-line
      {:ok, rates} = Money.ExchangeRates.historic_rates(date)

      assert rates["EUR"] == Decimal.new("0.85")
      assert rates["GBP"] == Decimal.new("0.73")
      assert rates["PLN"] == Decimal.new("4.05")

      assert {:ok, 1} = Ash.count(ExchangeRate, @bridge_opts)
    end

    test "Money.to_currency uses cached rates for conversion" do
      date = ~D[2024-01-15]

      seeded_rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("2.0"),
        "PLN" => Decimal.new("2.0")
      }

      DatabaseCache.store_historic_rates(nil, seeded_rates, date)

      # credo:disable-for-next-line
      {:ok, rates} = Money.ExchangeRates.historic_rates(date)

      eur_money = Money.new("EUR", Decimal.new("100"))
      {:ok, usd_money} = Money.to_currency(eur_money, "USD", rates)

      assert Money.to_decimal(usd_money) == Decimal.new("50.0")
    end

    test "Converter.normalize_amount_to_pln uses cached rates" do
      date = ~D[2024-01-15]

      seeded_rates = %{
        "USD" => Decimal.new("1.0"),
        "EUR" => Decimal.new("1.0"),
        "PLN" => Decimal.new("2.0")
      }

      DatabaseCache.store_historic_rates(nil, seeded_rates, date)

      amount_eur = Decimal.new("100")
      amount_pln = Converter.normalize_amount_to_pln(amount_eur, "EUR", date)

      expected_pln = Decimal.new("200")

      assert amount_pln == expected_pln

      assert {:ok, 1} = Ash.count(ExchangeRate, @bridge_opts)
    end
  end

  describe "historic_rates/2" do
    test "returns error when no rates for date" do
      date = ~D[2024-01-15]
      assert {:error, {%Money.ExchangeRateError{}, _}} = DatabaseCache.historic_rates(nil, date)
    end

    test "returns rates when cached for date" do
      date = ~D[2024-01-15]
      rates = %{"EUR" => Decimal.new("0.85"), "GBP" => Decimal.new("0.73")}
      DatabaseCache.store_historic_rates(nil, rates, date)

      assert {:ok, fetched_rates} = DatabaseCache.historic_rates(nil, date)
      assert fetched_rates["EUR"] == Decimal.new("0.85")
      assert fetched_rates["GBP"] == Decimal.new("0.73")
    end

    test "stores different rates for different dates" do
      date1 = ~D[2024-01-15]
      date2 = ~D[2024-01-16]
      rates1 = %{"EUR" => Decimal.new("0.85")}
      rates2 = %{"EUR" => Decimal.new("0.90")}

      DatabaseCache.store_historic_rates(nil, rates1, date1)
      DatabaseCache.store_historic_rates(nil, rates2, date2)

      assert {:ok, fetched_rates1} = DatabaseCache.historic_rates(nil, date1)
      assert fetched_rates1["EUR"] == Decimal.new("0.85")

      assert {:ok, fetched_rates2} = DatabaseCache.historic_rates(nil, date2)
      assert fetched_rates2["EUR"] == Decimal.new("0.90")
    end
  end

  describe "cleanup expired entries" do
    test "AshOban cleanup_expired destroys expired entries" do
      # Create expired entry via Ash
      Ash.Seed.seed!(ExchangeRate, %{
        cache_date: ~D[2023-01-01],
        rates: %{"EUR" => Decimal.new("0.85")},
        retrieved_at: DateTime.utc_now(),
        expires_at: DateTime.shift(DateTime.utc_now(), day: -1)
      })

      # Create non-expired entry
      Ash.Seed.seed!(ExchangeRate, %{
        cache_date: ~D[2024-01-01],
        rates: %{"EUR" => Decimal.new("0.90")},
        retrieved_at: DateTime.utc_now(),
        expires_at: DateTime.shift(DateTime.utc_now(), day: 30)
      })

      assert {:ok, 2} = Ash.count(ExchangeRate, @bridge_opts)

      # Read expired entries — should find only the expired one
      %{results: expired} =
        ExchangeRate.read_expired!(
          %{},
          authorize?: false,
          actor: %{},
          page: [limit: 100]
        )

      assert length(expired) == 1
      assert hd(expired).cache_date == ~D[2023-01-01]

      # Destroy it via the cleanup action
      Ash.destroy!(hd(expired), action: :cleanup_expired, authorize?: false, actor: %{})

      assert {:ok, 1} = Ash.count(ExchangeRate, @bridge_opts)
    end
  end
end
