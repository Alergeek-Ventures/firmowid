defmodule Firmowid.Ash.Invoicing.Matching.Assistant.CommonTools do
  @moduledoc false
  alias Firmowid.Ash.Currencies.Converter, as: Currencies
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.Matching.Assistant.FilterValidation
  alias Firmowid.Ash.Invoicing.Matching.Assistant.Tool
  alias Firmowid.Ash.Invoicing.Matching.CostInvoiceAssistant
  alias Firmowid.Repo

  def normalize_to_pln do
    %Tool{
      name: "normalize_to_pln",
      description:
        "Przelicz kwotę w dowolnej walucie na PLN, używając podanej kwoty, kodu waluty i daty (YYYY-MM-DD). Używaj tego narzędzia przed porównywaniem lub wyszukiwaniem po kwocie.",
      args_schema: %{
        type: "object",
        properties: %{
          amount: %{type: "number", description: "Kwota do przeliczenia"},
          currency: %{type: "string", description: "Kod waluty (np. 'EUR', 'USD', 'PLN')"},
          date: %{type: "string", format: "date", description: "Data kursu waluty (YYYY-MM-DD)"}
        },
        required: ["amount", "currency", "date"]
      },
      llm_render: fn
        {:error, error} -> "Błąd: #{error}"
        result -> Decimal.to_string(result)
      end,
      handler: fn args ->
        allowed_keys = ["amount", "currency", "date"]

        filtered =
          args
          |> Enum.filter(fn
            {k, v} -> k in allowed_keys and v not in ["", nil, []]
          end)
          |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

        case FilterValidation.validate_normalize_to_pln(filtered) do
          {:ok, %{amount: amount, currency: currency, date: date}} ->
            Currencies.normalize_amount_to_pln(amount, currency, date)

          {:error, error} ->
            {:error, error}
        end
      end
    }
  end

  def calculate do
    %Tool{
      name: "calculate",
      description:
        "Wykonaj działanie matematyczne (dodawanie, odejmowanie, mnożenie, dzielenie) na liście liczb. Wszystkie liczby są traktowane jako dziesiętne. Zwraca wynik jako liczbę dziesiętną.",
      args_schema: %{
        type: "object",
        properties: %{
          numbers: %{
            type: "array",
            items: %{
              type: "number",
              description: "Liczba"
            },
            description: "Niepusta lista liczb do obliczenia"
          },
          operation: %{
            type: "string",
            enum: ["+", "-", "*", "/"],
            description: "Działanie do wykonania: +, -, *, /"
          }
        },
        required: ["numbers", "operation"]
      },
      llm_render: fn
        {:error, error} -> "Błąd: #{error}"
        result -> Decimal.to_string(result)
      end,
      handler: fn args ->
        allowed_keys = ["numbers", "operation"]

        filtered =
          args
          |> Enum.filter(fn
            {k, v} -> k in allowed_keys and v not in ["", nil, []]
          end)
          |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

        case FilterValidation.validate_calculate(filtered) do
          {:ok, %{numbers: numbers, operation: operation}} ->
            case operation do
              "+" ->
                Enum.reduce(numbers, &Decimal.add/2)

              "-" ->
                Enum.reduce(numbers, &Decimal.sub/2)

              "*" ->
                Enum.reduce(numbers, &Decimal.mult/2)

              "/" ->
                try do
                  Enum.reduce(numbers, &Decimal.div/2)
                rescue
                  Decimal.Error -> {:error, "Dzielenie przez zero"}
                end
            end

          {:error, error} ->
            {:error, error}
        end
      end
    }
  end

  def search_transactions(opts) do
    negative = Keyword.fetch!(opts, :negative)

    %Tool{
      name: "search_transactions",
      description:
        "Wyszukaj transakcje bankowe za pomocą elastycznych filtrów. To JEDYNY sposób na dostęp do danych o transakcjach. MUSISZ wywołać tę funkcję za każdym razem, gdy chcesz znaleźć lub wylistować transakcje. Zwraca maksymalnie 50 najtrafniejszych wyników.",
      args_schema: %{
        type: "object",
        properties: %{
          filters: %{
            type: "object",
            description:
              "Pary klucz-wartość do filtrowania transakcji. Dozwolone klucze: query, date_from, date_to, amount_gt, amount_lt, only_unmatched.",
            properties: %{
              query: %{
                type: "string",
                description:
                  "Fraza do wyszukania w nazwach kontrahentów i opisach transakcji. Jeśli nie chcesz filtrować po tekście, zostaw puste."
              },
              date_from: %{
                type: ["string", "null"],
                format: "date",
                description: "Data od (YYYY-MM-DD). Jeśli nie chcesz filtrować po dacie, zostaw puste."
              },
              date_to: %{
                type: ["string", "null"],
                format: "date",
                description: "Data do (YYYY-MM-DD). Jeśli nie chcesz filtrować po dacie, zostaw puste."
              },
              currency: %{
                type: "string",
                description:
                  "Kod waluty (np. 'PLN', 'EUR') - używane do filtrowania transakcji. Wymagane jeśli filtrujesz po kwocie transakcji. Jeśli nie chcesz filtrować po walucie ani kwocie, zostaw puste."
              },
              amount_gt: %{
                type: ["number", "null"],
                description:
                  "Dodatnia kwota od której kwoty transakcji są większe lub równe. Jeśli nie chcesz filtrować po kwocie, zostaw puste."
              },
              amount_lt: %{
                type: ["number", "null"],
                description:
                  "Dodatnia kwota od której kwoty transakcji są mniejsze lub równe. Jeśli nie chcesz filtrować po kwocie, zostaw puste."
              },
              only_unmatched: %{
                type: "boolean",
                description:
                  "Pomiń transakcje, które są już dopasowane. false - wszystkie, true - tylko te, które nie są dopasowane. Domyślnie true."
              }
            },
            additionalProperties: false
          }
        },
        required: ["filters"]
      },
      llm_render: fn
        {:error, error} ->
          "Błąd: #{error}"

        :halt ->
          :halt

        result ->
          Enum.map_join(
            result,
            "\n\n",
            &CostInvoiceAssistant.transaction_input(&1, heading_level: 2)
          )
      end,
      handler: fn args ->
        allowed_keys = [
          "query",
          "date_from",
          "date_to",
          "amount_gt",
          "amount_lt",
          "only_unmatched",
          "currency"
        ]

        filters =
          case Map.get(args, "filters") do
            filters when is_map(filters) -> filters
            _ -> :halt
          end

        case filters do
          filters when is_map(filters) ->
            filtered =
              filters
              |> Enum.filter(fn
                {k, v} -> k in allowed_keys and v not in ["", nil, []]
              end)
              |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

            case FilterValidation.validate_search_filters(filtered) do
              {:ok, validated_filtered} ->
                final_filtered =
                  if negative do
                    validated_filtered =
                      validated_filtered
                      |> Map.replace_lazy(:amount_lt, fn amount_lt -> "-#{amount_lt}" end)
                      |> Map.replace_lazy(:amount_gt, fn amount_gt -> "-#{amount_gt}" end)

                    amount_lt = Map.get(validated_filtered, :amount_lt, nil)
                    amount_gt = Map.get(validated_filtered, :amount_gt, nil)

                    validated_filtered
                    |> Map.put(:amount_lt, amount_gt)
                    |> Map.put(:amount_gt, amount_lt)
                  else
                    validated_filtered
                  end

                search_transactions_via_ash(final_filtered)

              {:error, error} ->
                {:error, error}
            end

          _ ->
            :halt
        end
      end
    }
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp search_transactions_via_ash(params) do
    ash_args =
      params
      |> Map.take([:query, :date_from, :date_to])
      |> then(fn args ->
        only_unmatched = Map.get(params, :only_unmatched, true)
        if only_unmatched, do: Map.put(args, :status, :pending), else: args
      end)

    query =
      Transaction
      |> Ash.Query.for_read(:read, ash_args,
        authorize?: false,
        actor: %{},
        tenant: Repo.get_org_id()
      )
      |> Ash.Query.load([:cost_invoices, :sales_invoices])
      |> Ash.Query.limit(50)
      |> then(fn q ->
        # Only add default sort when ParadeDB search isn't overriding it
        if Map.get(params, :query) in [nil, ""],
          do: Ash.Query.sort(q, booking_date: :desc),
          else: q
      end)

    case Ash.read(query) do
      {:ok, results} ->
        results
        |> maybe_filter_in_memory(:currency, Map.get(params, :currency))
        |> maybe_filter_in_memory(:amount_gt, Map.get(params, :amount_gt))
        |> maybe_filter_in_memory(:amount_lt, Map.get(params, :amount_lt))

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_filter_in_memory(results, _field, nil), do: results

  defp maybe_filter_in_memory(results, :currency, val) do
    Enum.filter(results, &(&1.transaction_currency == val))
  end

  defp maybe_filter_in_memory(results, :amount_gt, val) do
    val = Decimal.new(to_string(val))
    Enum.filter(results, &(Decimal.compare(&1.transaction_amount, val) in [:gt, :eq]))
  end

  defp maybe_filter_in_memory(results, :amount_lt, val) do
    val = Decimal.new(to_string(val))
    Enum.filter(results, &(Decimal.compare(&1.transaction_amount, val) in [:lt, :eq]))
  end
end
