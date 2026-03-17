defmodule Firmowid.Invoicing.Matching.CostInvoiceAssistant do
  @moduledoc """
  Invoice-matching assistant: defines prompt, tools, and function handlers for invoice-to-transaction matching.
  Delegates LLM and function-call plumbing to AssistantEngine.
  """
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.Matching.Assistant.CommonTools
  alias Firmowid.Invoicing.Matching.Assistant.Engine
  alias Firmowid.Invoicing.Matching.Assistant.Message
  alias Firmowid.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Invoicing.Matching.Assistant.Tool

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
        cost_invoice = cost_invoice_ids |> hd() |> Firmowid.CostInvoices.get_cost_invoice!()
        organization_id = cost_invoice.organization_id

        Firmowid.CostInvoices.create_cost_invoices_transactions_connection(
          cost_invoice_ids,
          transaction_ids,
          organization_id
        )

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
      CommonTools.normalize_to_pln(),
      CommonTools.calculate(),
      CommonTools.search_transactions(negative: true),
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
          cost_invoice_id = List.first(cost_invoice_ids)

          cost_invoice =
            if cost_invoice_id do
              Firmowid.CostInvoices.get_cost_invoice(cost_invoice_id)
            end

          transactions = Firmowid.Finances.get_transactions!(transaction_ids)

          hallucinated_invoice = is_nil(cost_invoice)

          hallucinated_transactions =
            transaction_ids
            |> MapSet.new()
            |> MapSet.difference(MapSet.new(transactions, & &1.id))

          if hallucinated_invoice or not Enum.empty?(hallucinated_transactions) do
            error =
              [
                "Nie mogę połączyć faktury kosztowej z transakcjami, ponieważ nie mogę znaleźć faktury lub transakcji. Sprawdź, czy podałeś poprawne UUID.",
                hallucinated_invoice ||
                  "Nie znaleziono faktury o podanym ID #{cost_invoice_id}.",
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

  defp system_prompt(%CostInvoice{} = invoice) do
    """
    # Wprowadzenie

    Jesteś pomocnym asystentem, polskojęzycznym ekspertem od księgowości i finansów.
    Pomagasz osobie, która zarządza finansami i fakturowaniem w firmie.

    BEZWZGLĘDNA ZASADA JĘZYKOWA: Cała komunikacja — odpowiedzi, myślenie,
    rozumowanie, podsumowania rozumowania (reasoning summaries) — MUSI być
    wyłącznie po polsku. Nigdy nie używaj angielskiego.

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
    co widnieje na fakturze. Może zdarzyć się, że nazwa nie jest faktyczną nazwą firmy,
    lecz nazwą systemu płatności.

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

    ### Dopasowywanie okresów rozliczeniowych (WAŻNE)

    Faktury dotyczą konkretnych okresów rozliczeniowych (zazwyczaj jeden miesiąc kalendarzowy).
    Gdy dobierasz transakcje do faktury:

    - **preferuj transakcje z jednego, spójnego okresu rozliczeniowego** — jeśli faktura jest
    za luty, bierz transakcje z datą wartości w lutym, nie ze stycznia ani marca
    - transakcje mogą mieć datę księgowania inną niż data wartości — **data wartości jest
    ważniejsza** przy przyporządkowaniu do okresu rozliczeniowego
    - jeśli wyszukiwanie zwraca transakcje z różnych miesięcy (np. data księgowania w marcu,
    ale data wartości w lutym), odfiltrowuj je starannie według daty wartości
    - jeśli po odfiltrowaniu zostają transakcje z pogranicza miesięcy lub sytuacja jest
    niejednoznaczna — **zapytaj użytkownika**, zamiast zakładać, które transakcje pasują
    - nie łącz transakcji od różnych kontrahentów w jedną fakturę, chyba że użytkownik
    wyraźnie to potwierdzi
    - zawsze zweryfikuj sumę wybranych transakcji kalkulatorem przed zaproponowaniem połączenia

    # Dopasowujesz do tej faktury:

    #{cost_invoice_input(invoice)}
    """
  end

  defp cost_invoice_input(%CostInvoice{} = invoice, options \\ []) do
    heading_level = Keyword.get(options, :heading_level, 1)

    """
    #{String.duplicate("#", heading_level)} Faktura kosztowa #{invoice.invoice_identifier}

    > **Opis:** #{invoice.description}

    - **Skrócona nazwa sprzedawcy:** #{invoice.seller_display_name}
    - **Pełna nazwa sprzedawcy:** #{invoice.seller}
    - **Adres sprzedawcy:** #{invoice.seller_address}
    - **Numer konta sprzedawcy:** #{invoice.account_number}
    - **Data wystawienia:** #{invoice.issue_date}
    - **Data płatności:** #{invoice.due_date}
    - **Kwota:** #{invoice.total_amount}
    - **Waluta:** #{invoice.currency}

    > UUID: `#{invoice.id}`
    """
  end

  def transaction_input(%Transaction{} = transaction, options \\ []) do
    heading_level = Keyword.get(options, :heading_level, 1)

    """
    #{String.duplicate("#", heading_level)} Transakcja

    > **Dodatkowe informacje z banku:** #{transaction.remittance_information_unstructured}

    - **Data księgowania:** #{transaction.booking_date}
    - **Data wartości:** #{transaction.value_date}
    - **Kwota:** #{transaction.transaction_amount}
    - **Waluta:** #{transaction.transaction_currency}
    - **Odbiorca:** #{transaction.debtor_name}
    - **Numer konta odbiorcy:** #{transaction.debtor_account}
    - **Nadawca:** #{transaction.creditor_name}
    - **Numer konta nadawcy:** #{transaction.creditor_account}
    - **Powiązane faktury kosztowe:** #{Enum.map_join(transaction.cost_invoices_transactions, ", ", & &1.id)}

    > UUID: `#{transaction.id}`
    """
  end
end
