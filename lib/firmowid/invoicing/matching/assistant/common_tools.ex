defmodule Firmowid.Invoicing.Matching.Assistant.CommonTools do
  alias Firmowid.Invoicing.Matching.Assistant.Tool
  alias Firmowid.Invoicing.Matching.CostInvoiceAssistant

  def normalize_to_pln do
    %Tool{
      name: "normalize_to_pln",
      description:
        "Przelicz kwotę w dowolnej walucie na PLN, używając podanej kwoty, kodu waluty i daty (YYYY-MM-DD). Używaj tego narzędzia przed porównywaniem lub wyszukiwaniem po kwocie.",
      args_schema: %{
        type: "object",
        properties: %{
          amount: %{type: "string", description: "Kwota jako string dziesiętny (np. '123.45')"},
          currency: %{type: "string", description: "Kod waluty (np. 'EUR', 'USD', 'PLN')"},
          date: %{type: "string", format: "date", description: "Data kursu waluty (YYYY-MM-DD)"}
        },
        required: ["amount", "currency", "date"]
      },
      llm_render: fn result -> Decimal.to_string(result) end,
      handler: fn %{"amount" => amount, "currency" => currency, "date" => date} ->
        {:ok, parsed_date} = Date.from_iso8601(date)
        decimal_amount = Decimal.new(amount)
        Firmowid.Currencies.normalize_amount_to_pln(decimal_amount, currency, parsed_date)
      end
    }
  end

  def calculate do
    %Tool{
      name: "calculate",
      description:
        "Wykonaj działanie matematyczne (dodawanie, odejmowanie, mnożenie, dzielenie) na liście liczb. Wszystkie liczby są traktowane jako dziesiętne. Zwraca wynik jako string.",
      args_schema: %{
        type: "object",
        properties: %{
          numbers: %{
            type: "array",
            items: %{
              type: "string",
              description: "Liczba jako string dziesiętny (np. '123.45') lub liczba"
            },
            description: "Lista liczb do obliczenia"
          },
          operation: %{
            type: "string",
            enum: ["+", "-", "*", "/"],
            description: "Działanie do wykonania: +, -, *, /"
          }
        },
        required: ["numbers", "operation"]
      },
      llm_render: fn result -> Decimal.to_string(result) end,
      handler: fn %{"numbers" => numbers, "operation" => operation} ->
        decimals =
          Enum.map(numbers, fn
            n when is_binary(n) -> Decimal.new(n)
            n when is_number(n) -> Decimal.from_float(n * 1.0)
            n -> raise "Invalid number: #{inspect(n)}"
          end)

        case operation do
          "+" -> Enum.reduce(decimals, &Decimal.add/2)
          "-" -> Enum.reduce(decimals, &Decimal.sub/2)
          "*" -> Enum.reduce(decimals, &Decimal.mult/2)
          "/" -> Enum.reduce(decimals, &Decimal.div/2)
          _ -> raise "Invalid operation: #{operation}"
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
                description: "Fraza do wyszukania w nazwach kontrahentów i opisach transakcji."
              },
              date_from: %{
                type: "string",
                format: "date",
                description: "Data od (YYYY-MM-DD)"
              },
              date_to: %{
                type: "string",
                format: "date",
                description: "Data do (YYYY-MM-DD)"
              },
              currency: %{
                type: "string",
                description:
                  "Kod waluty (np. 'PLN', 'EUR') - używane do filtrowania transakcji. Wymagane jeśli filtrujesz po kwocie transakcji."
              },
              amount_gt: %{
                type: "string",
                description:
                  "Dodatnia kwota transakcji większa lub równa (liczba dziesiętna jako string)"
              },
              amount_lt: %{
                type: "string",
                description:
                  "Dodatnia kwota transakcji mniejsza lub równa (liczba dziesiętna jako string)"
              },
              only_unmatched: %{
                type: "boolean",
                description:
                  "Pomiń transakcje, które są już dopasowane. false - wszystkie, true - tylko te, które nie są dopasowane."
              }
            },
            additionalProperties: false
          }
        },
        required: ["filters"]
      },
      llm_render: fn result ->
        result
        |> Enum.map(&CostInvoiceAssistant.transaction_input(&1, heading_level: 2))
        |> Enum.join("\n\n")
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

        filtered =
          args["filters"]
          |> Enum.filter(fn {k, _v} -> k in allowed_keys end)
          |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
          |> Map.new()

        filtered =
          if negative do
            filtered =
              filtered
              |> Map.replace_lazy(:amount_lt, fn amount_lt -> "-#{amount_lt}" end)
              |> Map.replace_lazy(:amount_gt, fn amount_gt -> "-#{amount_gt}" end)

            amount_lt = Map.get(filtered, :amount_lt, nil)
            amount_gt = Map.get(filtered, :amount_gt, nil)

            filtered
            |> Map.put(:amount_lt, amount_gt)
            |> Map.put(:amount_gt, amount_lt)
          else
            filtered
          end

        Firmowid.Finances.search_transactions(filtered)
      end
    }
  end
end
