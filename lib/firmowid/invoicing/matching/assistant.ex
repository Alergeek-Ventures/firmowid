defmodule Firmowid.Invoicing.Matching.Assistant do
  @moduledoc """
  Invoice-matching assistant: defines prompt, tools, and function handlers for invoice-to-transaction matching.
  Delegates LLM and function-call plumbing to AssistantEngine.
  """
  alias Firmowid.Invoicing.Matching.Assistant.{Engine, Tool, MessagesStorage, Message, Input}
  alias Firmowid.CostInvoices.CostInvoice

  @intro_message ~S"""
  Cześć, tu Firmowid!
  Żeby pomóc Ci znaleźć transakcję, potrzebuję trochę więcej informacji. Możesz wpisać je tutaj albo skorzystać z jednej z podpowiedzi poniżej.
  """

  @doc """
  Starts a new conversation for a given invoice, returns conversation_id.
  """
  def start_conversation(invoice) do
    conversation_id = UUIDv7.generate()
    MessagesStorage.set_invoice(conversation_id, invoice)
    MessagesStorage.append(conversation_id, Message.new(:assistant, @intro_message))
    conversation_id
  end

  def send_message_streaming(conversation_id, message) do
    invoice = MessagesStorage.get_invoice(conversation_id)

    Engine.send_message_streaming(
      conversation_id,
      message,
      system_prompt(invoice),
      tools()
    )
  end

  def accept_linking(conversation_id) do
    msg = MessagesStorage.get_latest(conversation_id)

    case msg do
      %Message{
        role: :function_call,
        payload: %{
          name: "link_cost_invoice_to_transaction",
          args: %{"transaction_ids" => transaction_ids, "cost_invoice_ids" => cost_invoice_ids}
        }
      } ->
        cost_invoice = Firmowid.CostInvoices.get_cost_invoice!(cost_invoice_ids |> hd())
        organization_id = cost_invoice.organization_id

        # todo insert_all
        for cost_invoice_id <- cost_invoice_ids, transaction_id <- transaction_ids do
          Firmowid.CostInvoices.create_cost_invoices_transactions_connection(
            cost_invoice_id,
            transaction_id,
            organization_id
          )
        end

        MessagesStorage.delete(conversation_id)

      _ ->
        raise "Accepting linking is only allowed when the last message was a function call to link_cost_invoice_to_transaction"
    end
  end

  def reject_linking(conversation_id) do
    msg = MessagesStorage.get_latest(conversation_id)

    case msg do
      %Message{
        role: :function_call,
        payload: %{name: "link_cost_invoice_to_transaction", call_id: call_id}
      } ->
        MessagesStorage.append(
          conversation_id,
          Message.new(
            :function_result,
            "Użytkownik odrzucił połączenie faktury z transakcjami.",
            %{name: "link_cost_invoice_to_transaction", call_id: call_id}
          )
        )

      _ ->
        raise "Rejecting linking is only allowed when the last message was a function call to link_cost_invoice_to_transaction"
    end
  end

  @doc """
  Returns the list of tools (as Tool structs) available to the assistant.
  """
  def tools do
    [
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
                    "Kod waluty (np. 'PLN', 'EUR') - używane do filtrowania transakcji."
                },
                amount_gt: %{
                  type: "string",
                  description:
                    "Kwota transakcji większa lub równa (liczba dziesiętna jako string)"
                },
                amount_lt: %{
                  type: "string",
                  description:
                    "Kwota transakcji mniejsza lub równa (liczba dziesiętna jako string)"
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
          |> Enum.map(&Input.transaction_input(&1, heading_level: 2))
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

          Firmowid.Finances.search_transactions(filtered)
        end
      },
      %Tool{
        name: "normalize_to_pln",
        description:
          "Przelicz kwotę w dowolnej walucie na PLN, używając podanej kwoty, kodu waluty i daty (YYYY-MM-DD). ZAWSZE używaj tego narzędzia przed porównywaniem lub wyszukiwaniem po kwocie.",
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
      },
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
      },
      %Tool{
        name: "link_cost_invoice_to_transaction",
        description: """
        Pyta użytkownika o potwierdzenie przed połączeniem faktur kosztowych z transakcjami.
        Możesz podać wiele transakcji i wiele faktur, narzędzie połączy każdą z każdą.
        To pozwala na połączenie jeden do wielu w obie strony, a także jeden do jeden.
        Nie pytaj użytkownika o potwierdzenie przed użyciem tego narzędzia,
        ponieważ użytkownik będzie potwierdzał połączenie w interfejsie.

        Użyj tego narzędzia, gdy masz pewność, że transakcje pasują do faktur.
        """,
        args_schema: %{
          type: "object",
          properties: %{
            message: %{
              type: "string",
              description:
                "Wiadomości która wyświetli się użytkownikowi. Zawrzyj w niej informacje o sumie transakcji i ich ilości. np: Znalazłem 2 pasujące transakcje - ich suma wynosi 80,00 PLN."
            },
            cost_invoice_ids: %{
              type: "array",
              items: %{type: "string"},
              description: "Lista UUID faktur kosztowych"
            },
            transaction_ids: %{
              type: "array",
              items: %{type: "string"},
              description: "Lista UUID transakcji"
            }
          },
          required: ["cost_invoice_ids", "transaction_ids"]
        },
        llm_render: &elem(&1, 1),
        handler: fn %{
                      "cost_invoice_ids" => cost_invoice_ids,
                      "transaction_ids" => transaction_ids
                    } ->
          cost_invoice = Firmowid.CostInvoices.get_cost_invoice(cost_invoice_ids |> hd())
          transactions = Firmowid.Finances.get_transactions!(transaction_ids)

          hallucinated_invoice = is_nil(cost_invoice)

          hallucinated_transactions =
            MapSet.new(transaction_ids)
            |> MapSet.difference(MapSet.new(transactions, & &1.id))

          if hallucinated_invoice or not Enum.empty?(hallucinated_transactions) do
            error =
              [
                "Nie mogę połączyć faktury kosztowej z transakcjami, ponieważ nie mogę znaleźć faktury lub transakcji. Sprawdź, czy podałeś poprawne UUID.",
                hallucinated_invoice ||
                  "Nieznaleziono faktury o podanym ID #{hd(cost_invoice_ids)}.",
                not Enum.empty?(hallucinated_transactions) ||
                  "Nie znaleziono transakcji o podanych ID: #{Enum.join(hallucinated_transactions, ", ")}."
              ]
              |> Enum.filter(&is_binary/1)
              |> Enum.join(" ")

            {:error, error}
          else
            :halt
          end
        end
      }
    ]
  end

  defp system_prompt(invoice = %CostInvoice{}) do
    """
    # Wprowadzenie

    Jesteś pomocnym asystentem, polskojęzycznym ekspertem od księgowości i finansów.
    Pomagasz osobie, która zarządza finansami i fakturowaniem w firmie.

    # Cel

    Twoim zadaniem jest pomóc znaleźć transakcje, które pasują do faktury.
    Czasami jest to pojedyncza transakcja, czasami grupa transakcji,
    a czasami do jednej transakcji pasuje wiele faktur.

    ## Kontekst

    Wytrenowany model uczenia maszynowego już zasugerował listę transakcji,
    które według niego pasują do tej faktury. Jeśli jednak użytkownik zwraca
    się do Ciebie, oznacza to, że propozycje modelu nie były wystarczająco dobre
    lub sytuacja jest zbyt nietypowa, aby model sobie z nią poradził.

    Aby wykonać to zadanie, zacznij od poproszenia użytkownika o opisanie sytuacji.
    Mając ten kontekst, użyj dostępnych narzędzi, aby znaleźć najlepsze dopasowanie.
    Jeśli masz jakiekolwiek wątpliwości, poproś użytkownika o doprecyzowanie.

    Użytkownik zazwyczaj posiada dodatkowy kontekst, który powinien naprowadzić Cię
    na właściwe rozwiązanie.

    Pamiętaj, że wszelakie nazwy własne często nie są dobre do wyszukiwania. Kontrahenci
    widniejący w bazie transakcji są zazwyczaj nazwami firm, które mogą być rozbieżne z tym
    co widnieje na fakturze.

    ## Narzędzia

    Masz dostęp do następujących narzędzi - korzystaj z nich przy rozwiązywaniu zadania:

    1. `search_transactions`: Za każdym razem, gdy potrzebujesz wyszukać transakcje,
    MUSISZ użyć tego narzędzia. To JEDYNY sposób na dostęp do danych o transakcjach.

    2. `normalize_to_pln`: Za każdym razem, gdy musisz porównać lub filtrować kwoty,
    MUSISZ dbać o waluty - często płatności w zagranicznych są wykonywane przez polskie
    sposoby płatności i widnieją jako PLN - ale z sumą po konwersji walut. Dlatego przed
    przeszukiwaniem bazy transakcji, musisz przeliczyć kwotę na PLN za pomocą tego
    narzędzia.

    3. `calculate`: Za każdym razem, gdy musisz wykonać działanie matematyczne,
    użyj tego narzędzia zamiast polegać na intuicji przy obliczeniach.

    4. `link_cost_invoice_to_transaction`: Pyta użytkownika o potwierdzenie przed połączeniem faktur kosztowych z transakcjami.
    Możesz podać wiele transakcji i wiele faktur, narzędzie połączy każdą z każdą.
    To pozwala na połączenie jeden do wielu w obie strony, a także jeden do jeden.
    Nie pytaj użytkownika o potwierdzenie przed użyciem tego narzędzia,
    ponieważ użytkownik będzie potwierdzał połączenie w interfejsie.
    Jeśli użytkownik odrzuci połączenie, nie komentuj tego, czekaj na dodatkowe informację od niego.

    ## Przykładowe rozwiązania zadania

    ### Faktura

    Data: 2025-07-04
    Kwota: -216.00
    Waluta: PLN
    Sprzedawca (nazwa skrócona): China Telecom
    Numer konta sprzedawcy: N/A
    Opis: Usługi telekomunikacyjne, doładowania oraz pakiet danych.

    ### Transakcje

    #### Transakcja 1

    Data: 2025-06-13
    Kwota: -36.00
    Waluta: PLN
    Sprzedawca (nazwa skrócona): chinatel.co
    Numer konta sprzedawcy: płatność kartą
    Opis: 155/X/321

    #### Transakcja 2

    Data: 2025-06-13
    Kwota: -10.00
    Waluta: PLN
    Sprzedawca (nazwa skrócona): chinatel.co
    Numer konta sprzedawcy: płatność kartą
    Opis: 155/X/321

    #### Transakcja 3

    Data: 2025-06-13
    Kwota: -100.00
    Waluta: PLN
    Sprzedawca (nazwa skrócona): chinatel.co
    Numer konta sprzedawcy: płatność kartą
    Opis: 125/Z/221

    #### Transakcja 4

    Data: 2025-06-13
    Kwota: -70.00
    Waluta: PLN
    Sprzedawca (nazwa skrócona): chinatel.co
    Numer konta sprzedawcy: płatność kartą
    Opis: 2/4fwZ/001

    ### Rozwiązanie

    - Użytkownik poinformował asystenta, że faktura ma wiele transakcji z poprzedniego miesiąca.
    - Asystent przeszukał bazę transakcji, zwrócił uwagę na powtarzających się kontrahentów.
    - Po doprecyzowaniu z użytkownikiem, asystent skorzystał z narzędzia kalkulatora, dodając kwoty
    transakcji i uzyskał wynik, który pasował do kwoty na fakturze.
    - Asystent używał narzędzia do łączenia faktur z transakcjami.
    - Użytkownik potwierdza połączenie.

    ### Rekomendacje

    - gdy szukasz, zacznij od szerokiego przeszukiwania bazy - na podstawie odpowiedzi zastanów się
    jaka powinna być dalsza operacja, użytkownik będzie pomagać odpowiadając na Twoje pytania
    - nigdy nie zaczynaj od szukania po nazwie kontrahenta czy produktu - stosuj bardzo luźne filtry
    i zawężaj dopiero na podstawie rezultatów wyszukiwania oraz podpowiedzi użytkownika
    - gdy szukasz, korzystaj z tego co mówi Ci użytkownik - jeżeli mówi o zeszłym miesiącu,
    to nie zawężaj parametrów wyszukiwania, np.: podając nazwę kontrahenta
    - transakcje pominięte są zwykle nieprzydatne, dlatego domyślnie nie będą przeszukiwane - natomiast
    możesz zasugerować użytkownikowi, aby rozszerzyć wyszukiwanie o pominięte transakcje
    - pominięte transakcje to takie, które już mają przyporządkowane faktury bądź nie są dokumentowane
    fakturami (jak pensje bądź podatki)
    - bądź zwięzły w wypowiedziach, użytkownik wie dokładnie jaki jest cel interakcji (zadanie), więc
    nie musisz mówić za wiele o tym, co robisz
    - nie wypisuj identyfikatorów (UUID) w wiadomościach, użytkownikowi nie są one potrzebne,
    tylko Tobie aby wykorzystać je w narzędziach
    - pierwsze wyszukiwanie transakcji powinno być tylko po datach

    # Dopasowujesz do tej faktury:

    #{Input.cost_invoice_input(invoice)}
    """
  end
end
