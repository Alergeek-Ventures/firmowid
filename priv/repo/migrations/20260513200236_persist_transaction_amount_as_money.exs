defmodule Firmowid.Repo.Migrations.PersistTransactionAmountAsMoney do
  @moduledoc """
  Flattened branch-local migration that installs ash_money support and
  migrates transactions from split amount/currency fields to a persisted
  composite money value.
  """

  use Ecto.Migration

  def up do
    execute "CREATE TYPE public.money_with_currency AS (currency_code varchar, amount numeric);"

    execute """
    CREATE OR REPLACE FUNCTION money_gt(money_1 public.money_with_currency, money_2 public.money_with_currency)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        IF currency_code(money_1) = currency_code(money_2) THEN
          currency := currency_code(money_1);
          result := amount(money_1) > amount(money_2);
          return result;
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes for > operator. Expected both currency codes to be %', currency_code(money_1)
            USING HINT = 'Please ensure both columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_gt(money_1 public.money_with_currency, amount numeric)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        currency := currency_code(money_1);
        result := amount(money_1) > amount;
        return result;
      END;
    $$;
    """

    execute """
    CREATE OPERATOR > (
        leftarg = public.money_with_currency,
        rightarg = public.money_with_currency,
        procedure = money_gt
    );
    """

    execute """
    CREATE OPERATOR > (
        leftarg = public.money_with_currency,
        rightarg = numeric,
        procedure = money_gt
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_gte(money_1 public.money_with_currency, money_2 public.money_with_currency)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        IF currency_code(money_1) = currency_code(money_2) THEN
          currency := currency_code(money_1);
          result := amount(money_1) >= amount(money_2);
          return result;
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes for >= operator. Expected both currency codes to be %', currency_code(money_1)
            USING HINT = 'Please ensure both columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_gte(money_1 public.money_with_currency, amount numeric)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        currency := currency_code(money_1);
        result := amount(money_1) >= amount;
        return result;
      END;
    $$;
    """

    execute """
    CREATE OPERATOR >= (
        leftarg = public.money_with_currency,
        rightarg = public.money_with_currency,
        procedure = money_gte
    );
    """

    execute """
    CREATE OPERATOR >= (
        leftarg = public.money_with_currency,
        rightarg = numeric,
        procedure = money_gte
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_lt(money_1 money_with_currency, money_2 money_with_currency)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        IF currency_code(money_1) = currency_code(money_2) THEN
          currency := currency_code(money_1);
          result := amount(money_1) < amount(money_2);
          return result;
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes for < operator. Expected both currency codes to be %', currency_code(money_1)
            USING HINT = 'Please ensure both columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_lt(money_1 money_with_currency, amount numeric)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        currency := currency_code(money_1);
        result := amount(money_1) < amount;
        return result;
      END;
    $$;
    """

    execute """
    CREATE OPERATOR < (
        leftarg = money_with_currency,
        rightarg = money_with_currency,
        procedure = money_lt
    );
    """

    execute """
    CREATE OPERATOR < (
        leftarg = money_with_currency,
        rightarg = numeric,
        procedure = money_lt
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_lte(money_1 money_with_currency, money_2 money_with_currency)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        IF currency_code(money_1) = currency_code(money_2) THEN
          currency := currency_code(money_1);
          result := amount(money_1) <= amount(money_2);
          return result;
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes for <= operator. Expected both currency codes to be %', currency_code(money_1)
            USING HINT = 'Please ensure both columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_lte(money_1 money_with_currency, amount numeric)
    RETURNS BOOLEAN
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        result boolean;
      BEGIN
        currency := currency_code(money_1);
        result := amount(money_1) <= amount;
        return result;
      END;
    $$;
    """

    execute """
    CREATE OPERATOR <= (
        leftarg = money_with_currency,
        rightarg = money_with_currency,
        procedure = money_lte
    );
    """

    execute """
    CREATE OPERATOR <= (
        leftarg = money_with_currency,
        rightarg = numeric,
        procedure = money_lte
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_sub(money_1 money_with_currency, money_2 money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        subtraction numeric;
      BEGIN
        IF currency_code(money_1) = currency_code(money_2) THEN
          currency := currency_code(money_1);
          subtraction := amount(money_1) - amount(money_2);
          return row(currency, subtraction);
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes for - operator. Expected both currency codes to be %', currency_code(money_1)
            USING HINT = 'Please ensure both columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OPERATOR - (
        leftarg = money_with_currency,
        rightarg = money_with_currency,
        procedure = money_sub,
        commutator = -
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_neg(money_1 money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        addition numeric;
      BEGIN
        currency := currency_code(money_1);
        addition := amount(money_1) * -1;
        return row(currency, addition);
      END;
    $$;
    """

    execute """
    CREATE OPERATOR - (
        rightarg = money_with_currency,
        procedure = money_neg
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_add(money_1 money_with_currency, money_2 money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        addition numeric;
      BEGIN
        IF currency_code(money_1) = currency_code(money_2) THEN
          currency := currency_code(money_1);
          addition := amount(money_1) + amount(money_2);
          return row(currency, addition);
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes for + operator. Expected both currency codes to be %', currency_code(money_1)
            USING HINT = 'Please ensure both columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OPERATOR + (
        leftarg = money_with_currency,
        rightarg = money_with_currency,
        procedure = money_add,
        commutator = +
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_min_state_function(agg_state money_with_currency, money money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_currency varchar;
        aggregate numeric;
        min numeric;
      BEGIN
        IF currency_code(agg_state) IS NULL then
          expected_currency := currency_code(money);
          aggregate := 0;
        ELSE
          expected_currency := currency_code(agg_state);
          aggregate := amount(agg_state);
        END IF;

        IF currency_code(money) = expected_currency THEN
          IF amount(money) < aggregate THEN
            min := amount(money);
          ELSE
            min := aggregate;
          END IF;
          return row(expected_currency, min);
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes. Expected all currency codes to be %', expected_currency
            USING HINT = 'Please ensure all columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_min_combine_function(agg_state1 money_with_currency, agg_state2 money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        min numeric;
      BEGIN
        IF currency_code(agg_state1) = currency_code(agg_state2) THEN
          IF amount(agg_state1) < amount(agg_state2) THEN
            min := amount(agg_state1);
          ELSE
            min := amount(agg_state2);
          END IF;
          return row(currency_code(agg_state1), min);
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes. Expected all currency codes to be %', currency_code(agg_state1)
            USING HINT = 'Please ensure all columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE AGGREGATE min(money_with_currency)
    (
      sfunc = money_min_state_function,
      stype = money_with_currency,
      combinefunc = money_min_combine_function,
      parallel = SAFE
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_max_state_function(agg_state money_with_currency, money money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_currency varchar;
        aggregate numeric;
        max numeric;
      BEGIN
        IF currency_code(agg_state) IS NULL then
          expected_currency := currency_code(money);
          aggregate := 0;
        ELSE
          expected_currency := currency_code(agg_state);
          aggregate := amount(agg_state);
        END IF;

        IF currency_code(money) = expected_currency THEN
          IF amount(money) > aggregate THEN
            max := amount(money);
          ELSE
            max := aggregate;
          END IF;
          return row(expected_currency, max);
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes. Expected all currency codes to be %', expected_currency
            USING HINT = 'Please ensure all columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_max_combine_function(agg_state1 money_with_currency, agg_state2 money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        max numeric;
      BEGIN
        IF currency_code(agg_state1) = currency_code(agg_state2) THEN
          IF amount(agg_state1) > amount(agg_state2) THEN
            max := amount(agg_state1);
          ELSE
            max := amount(agg_state2);
          END IF;
          return row(currency_code(agg_state1), max);
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes. Expected all currency codes to be %', currency_code(agg_state1)
            USING HINT = 'Please ensure all columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE AGGREGATE max(money_with_currency)
    (
      sfunc = money_max_state_function,
      stype = money_with_currency,
      combinefunc = money_max_combine_function,
      parallel = SAFE
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_sum_state_function(agg_state money_with_currency, money money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        expected_currency varchar;
        aggregate numeric;
        addition numeric;
      BEGIN
        if currency_code(agg_state) IS NULL then
          expected_currency := currency_code(money);
          aggregate := 0;
        else
          expected_currency := currency_code(agg_state);
          aggregate := amount(agg_state);
        end if;

        IF currency_code(money) = expected_currency THEN
          addition := aggregate + amount(money);
          return row(expected_currency, addition);
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes. Expected all currency codes to be %', expected_currency
            USING HINT = 'Please ensure all columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_sum_combine_function(agg_state1 money_with_currency, agg_state2 money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF currency_code(agg_state1) = currency_code(agg_state2) THEN
          return row(currency_code(agg_state1), amount(agg_state1) + amount(agg_state2));
        ELSE
          RAISE EXCEPTION
            'Incompatible currency codes. Expected all currency codes to be %', currency_code(agg_state1)
            USING HINT = 'Please ensure all columns have the same currency code',
            ERRCODE = '22033';
        END IF;
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE AGGREGATE sum(money_with_currency)
    (
      sfunc = money_sum_state_function,
      stype = money_with_currency,
      combinefunc = money_sum_combine_function,
      parallel = SAFE
    );
    """

    execute """
    CREATE OR REPLACE FUNCTION money_mult(multiplicator numeric, money money_with_currency)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
      DECLARE
        currency varchar;
        multiplication numeric;
      BEGIN
          currency := currency_code(money);
          multiplication := amount(money) * multiplicator;
          return row(currency, multiplication);
      END;
    $$;
    """

    execute """
    CREATE OR REPLACE FUNCTION money_mult_reverse(money money_with_currency, multiplicator numeric)
    RETURNS money_with_currency
    IMMUTABLE
    STRICT
    LANGUAGE plpgsql
    AS $$
    BEGIN
        RETURN money_mult(multiplicator, money);
    END;
    $$;
    """

    execute """
    CREATE OPERATOR * (
        LEFTARG = numeric,
        RIGHTARG = money_with_currency,
        PROCEDURE = money_mult
    );
    """

    execute """
    CREATE OPERATOR * (
        LEFTARG = money_with_currency,
        RIGHTARG = numeric,
        PROCEDURE = money_mult_reverse
    );
    """

    alter table(:transactions) do
      add :amount, :money_with_currency
    end

    execute("""
    UPDATE transactions
    SET amount = ROW(transaction_currency, transaction_amount)::public.money_with_currency
    WHERE amount IS NULL
      AND transaction_currency IS NOT NULL
      AND transaction_amount IS NOT NULL
    """)

    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM transactions
        WHERE transaction_currency IS NOT NULL
          AND transaction_amount IS NOT NULL
          AND amount IS NULL
      ) THEN
        RAISE EXCEPTION
          'Transaction money backfill failed: some rows still have split money fields but no composite amount';
      END IF;
    END
    $$;
    """)

    execute(&validate_historical_transaction_currencies!/0, fn -> :ok end)

    alter table(:transactions) do
      remove :transaction_currency
      remove :transaction_amount
      modify :amount, :money_with_currency, null: false
    end

    execute("DROP INDEX IF EXISTS transactions_search_idx")

    execute("""
    CREATE INDEX transactions_search_idx
    ON transactions
    USING bm25 (id, debtor_name, creditor_name, remittance_information_unstructured)
    WITH (key_field='id', text_fields='{
      "debtor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "creditor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "remittance_information_unstructured": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}}
    }')
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS transactions_search_idx")

    alter table(:transactions) do
      add :transaction_amount, :decimal
      add :transaction_currency, :text
    end

    execute("""
    UPDATE transactions
    SET transaction_currency = (amount).currency_code,
        transaction_amount = (amount).amount
    WHERE amount IS NOT NULL
      AND transaction_currency IS NULL
      AND transaction_amount IS NULL
    """)

    alter table(:transactions) do
      remove :amount
    end

    execute("""
    CREATE INDEX transactions_search_idx
    ON transactions
    USING bm25 (id, debtor_name, creditor_name, remittance_information_unstructured, transaction_currency)
    WITH (key_field='id', text_fields='{
      "debtor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "creditor_name": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "remittance_information_unstructured": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}},
      "transaction_currency": {"tokenizer": {"type": "ngram", "min_gram": 2, "max_gram": 3, "prefix_only": false}}
    }')
    """)

    execute "DROP OPERATOR >=(public.money_with_currency, public.money_with_currency);"
    execute "DROP OPERATOR >=(public.money_with_currency, numeric);"

    execute """
    CREATE OPERATOR >= (
        leftarg = public.money_with_currency,
        rightarg = public.money_with_currency,
        procedure = money_gt
    );
    """

    execute """
    CREATE OPERATOR >= (
        leftarg = money_with_currency,
        rightarg = numeric,
        procedure = money_gt
    );
    """

    execute "DROP TYPE IF EXISTS public.money_with_currency CASCADE;"
  end

  defp validate_historical_transaction_currencies! do
    distinct_currency_codes =
      repo().query!("""
      SELECT DISTINCT currency_code
      FROM (
        SELECT transaction_currency AS currency_code
        FROM transactions
        WHERE transaction_currency IS NOT NULL

        UNION

        SELECT (amount).currency_code AS currency_code
        FROM transactions
        WHERE amount IS NOT NULL
      ) currencies
      ORDER BY currency_code
      """).rows
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    invalid_currency_codes =
      Enum.reject(distinct_currency_codes, fn currency_code ->
        match?({:ok, _currency}, Money.validate_currency(currency_code))
      end)

    if invalid_currency_codes != [] do
      raise """
      Cannot remove legacy transaction money fields because some historical transaction currencies are invalid for ash_money: #{Enum.join(invalid_currency_codes, ", ")}
      Normalize those rows first and rerun the migration.
      """
    end
  end
end
