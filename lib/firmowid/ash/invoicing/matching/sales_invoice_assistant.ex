# credo:disable-for-this-file ExDNA.Credo
# This assistant is intentionally parallel to CostInvoiceAssistant; meaningful deduplication
# needs extracting a shared assistant engine contract across both modules.
defmodule Firmowid.Ash.Invoicing.Matching.SalesInvoiceAssistant do
  # TODO: ~85% identical to CostInvoiceAssistant — extract shared InvoiceAssistant
  # with type parameter to reduce duplication.
  @moduledoc false
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Matching.Assistant.CommonTools
  alias Firmowid.Ash.Invoicing.Matching.Assistant.Engine
  alias Firmowid.Ash.Invoicing.Matching.Assistant.Message
  alias Firmowid.Ash.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Ash.Invoicing.Matching.Assistant.Tool
  alias Firmowid.Ash.Invoicing.SalesInvoice

  @intro_message ~S"""
  Cześć, tu Firmowid!
  Żeby pomóc Ci znaleźć transakcję, potrzebuję trochę więcej informacji. Możesz wpisać je tutaj albo skorzystać z jednej z podpowiedzi poniżej.
  """

  def start_conversation(invoice, scope) do
    conversation_id = UUIDv7.generate()
    MessagesStorage.set_invoice(conversation_id, invoice)
    MessagesStorage.set_scope(conversation_id, scope)
    MessagesStorage.append(conversation_id, Message.new(:assistant, @intro_message))
    conversation_id
  end

  def send_message_streaming(conversation_id, message) do
    invoice = MessagesStorage.get_invoice(conversation_id)
    scope = MessagesStorage.get_scope(conversation_id)

    case suggest_previous_month_aggregate(invoice, scope) do
      {:ok, transaction_ids, suggestion_message} ->
        send(self(), {:loading, true})

        user_message = Message.new(:user, message)
        send(self(), user_message)
        MessagesStorage.append(conversation_id, user_message)

        suggestion =
          Message.new(:function_call, "link_sales_invoice_to_transaction", %{
            name: "link_sales_invoice_to_transaction",
            args: %{
              "message" => suggestion_message,
              "sales_invoice_ids" => [invoice.id],
              "transaction_ids" => transaction_ids
            },
            call_id: UUIDv7.generate(),
            done: true
          })

        send(self(), suggestion)
        MessagesStorage.append(conversation_id, suggestion)

        send(self(), {:loading, false})
        :ok

      :no_suggestion ->
        Engine.send_message_streaming(
          conversation_id,
          message,
          system_prompt(invoice),
          tools(scope)
        )
    end
  end

  def accept_linking(conversation_id) do
    msg = MessagesStorage.get_latest(conversation_id)
    scope = MessagesStorage.get_scope(conversation_id)

    case msg do
      %Message{
        role: :function_call,
        payload: %{
          name: "link_sales_invoice_to_transaction",
          args: %{"transaction_ids" => transaction_ids, "sales_invoice_ids" => sales_invoice_ids}
        }
      } ->
        Enum.each(sales_invoice_ids, fn si_id ->
          sales_invoice = Invoicing.get_sales_invoice!(si_id, scope: scope)

          Invoicing.connect_sales_invoice_transactions!(
            sales_invoice,
            transaction_ids,
            scope: scope
          )
        end)

        MessagesStorage.delete(conversation_id)

      _ ->
        raise "Accepting linking is only allowed when the last message was a function call to link_sales_invoice_to_transaction"
    end
  end

  def reject_linking(conversation_id) do
    msg = MessagesStorage.get_latest(conversation_id)

    case msg do
      %Message{
        role: :function_call,
        payload: %{name: "link_sales_invoice_to_transaction", call_id: call_id}
      } ->
        MessagesStorage.append(
          conversation_id,
          Message.new(
            :function_result,
            "Użytkownik odrzucił połączenie faktury z transakcjami.",
            %{name: "link_sales_invoice_to_transaction", call_id: call_id}
          )
        )

      _ ->
        raise "Rejecting linking is only allowed when the last message was a function call to link_sales_invoice_to_transaction"
    end
  end

  def tools(scope) do
    [
      CommonTools.normalize_to_pln(),
      CommonTools.calculate(),
      CommonTools.search_transactions(negative: false, scope: scope),
      %Tool{
        name: "link_sales_invoice_to_transaction",
        description: """
        Pyta użytkownika o potwierdzenie przed połączeniem faktur sprzedażowych z transakcjami.
        Możesz podać wiele transakcji i wiele faktur, narzędzie połączy każdą z każdą.
        To pozwala na połączenie jeden do wielu w obie strony, a także jeden do jeden.
        Nie pytaj użytkownika o potwierdzenie przed użyciem tego narzędzia,
        ponieważ użytkownik będzie potwierdzał połączenie w interfejsie.
        """,
        args_schema: %{
          type: "object",
          properties: %{
            message: %{
              type: "string",
              description:
                "Wiadomości która wyświetli się użytkownikowi. Zawrzyj w niej informacje o sumie transakcji i ich ilości. np: Znalazłem 2 pasujące transakcje - ich suma wynosi 80,00 PLN."
            },
            sales_invoice_ids: %{
              type: "array",
              items: %{type: "string"},
              description: "Lista UUID faktur sprzedażowych"
            },
            transaction_ids: %{
              type: "array",
              items: %{type: "string"},
              description: "Lista UUID transakcji"
            }
          },
          required: ["sales_invoice_ids", "transaction_ids"]
        },
        llm_render: &elem(&1, 1),
        handler: fn %{
                      "sales_invoice_ids" => sales_invoice_ids,
                      "transaction_ids" => transaction_ids
                    } ->
          sales_invoice_id = List.first(sales_invoice_ids)

          sales_invoice =
            if sales_invoice_id do
              sales_invoice_id
              |> Invoicing.get_sales_invoice(scope: scope)
              |> case do
                {:ok, invoice} -> invoice
                _ -> nil
              end
            end

          transactions =
            Finances.list_transactions!(
              filter: [id: [in: transaction_ids]],
              scope: scope
            )

          hallucinated_invoice = is_nil(sales_invoice)

          hallucinated_transactions =
            transaction_ids
            |> MapSet.new()
            |> MapSet.difference(MapSet.new(transactions, & &1.id))

          if hallucinated_invoice or not Enum.empty?(hallucinated_transactions) do
            error =
              [
                "Nie mogę połączyć faktury sprzedażowej z transakcjami, ponieważ nie mogę znaleźć faktury lub transakcji. Sprawdź, czy podałeś poprawne UUID.",
                hallucinated_invoice ||
                  "Nieznaleziono faktury o podanym ID #{sales_invoice_id}.",
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

  defp system_prompt(%SalesInvoice{} = invoice) do
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
    Jeśli użytkownik wspomni o walucie transakcji, użyj filtru waluty.

    2. `normalize_to_pln`: Za każdym razem, gdy musisz porównać lub filtrować kwoty,
    MUSISZ dbać o waluty - często płatności w zagranicznych są wykonywane przez polskie
    sposoby płatności i widnieją jako PLN - ale z sumą po konwersji walut. Dlatego przed
    przeszukiwaniem bazy transakcji, warto przeliczyć kwotę na PLN za pomocą tego
    narzędzia, jeśli nic nie znajdziesz, to spróbuj ponownie bez tego narzędzia.

    3. `calculate`: Za każdym razem, gdy musisz wykonać działanie matematyczne,
    użyj tego narzędzia zamiast polegać na intuicji przy obliczeniach.

    4. `link_sales_invoice_to_transaction`: Łączy faktury sprzedażowe z transakcjami.
    Możesz podać wiele transakcji i wiele faktur, narzędzie połączy każdą z każdą.
    To pozwala na połączenie jeden do wielu w obie strony, a także jeden do jeden.
    Nie pytaj użytkownika o potwierdzenie przed użyciem tego narzędzia,
    ponieważ użytkownik będzie potwierdzał połączenie w interfejsie.
    Nie informuj użytkownika o tym, że używasz tego narzędzia.

    ## Przykładowe rozwiązania zadania

    ### Faktura

    Data: 2025-07-04
    Kwota: 216.00
    Waluta: PLN
    Kupujący: Kids Toys Sp. z o.o.
    Adres kupującego: ul. Koszerna 12, 00-001 Warszawa

    ### Transakcje

    #### Transakcja 1

    Data: 2025-06-13
    Kwota: -36.00
    Waluta: PLN
    Kupujący (nazwa skrócona): toys4kids
    Opis: 155/06/2025

    #### Transakcja 2

    Data: 2025-06-13
    Kwota: -10.00
    Waluta: PLN
    Kupujący (nazwa skrócona): toys4kids
    Opis: 155/06/2025

    #### Transakcja 3

    Data: 2025-06-13
    Kwota: -100.00
    Waluta: PLN
    Kupujący (nazwa skrócona): toys4kids
    Opis: 125/06/2025

    #### Transakcja 4

    Data: 2025-06-13
    Kwota: -70.00
    Waluta: PLN
    Kupujący (nazwa skrócona): toys4kids
    Opis: 2/06/2025

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
    - zwykle płatności następują po dacie wystawienia faktury i przed terminem płatności

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

    #{sales_invoice_input(invoice)}
    """
  end

  defp suggest_previous_month_aggregate(%SalesInvoice{} = invoice, scope) do
    invoice =
      Invoicing.get_sales_invoice!(invoice.id,
        load: [:buyer_display_name_label, :gross_value],
        scope: scope
      )

    with %Decimal{} = gross_value <- invoice.gross_value,
         buyer_name when is_binary(buyer_name) <- invoice.buyer_display_name_label do
      prev_month_ref = Date.shift(invoice.issue_date, month: -1)
      date_from = Date.beginning_of_month(prev_month_ref)
      date_to = Date.end_of_month(prev_month_ref)

      matching_transactions =
        %{date_from: date_from, date_to: date_to, reconciliation: :pending}
        |> Finances.list_transactions!(scope: scope)
        |> Enum.filter(fn tx ->
          Decimal.gt?(tx.transaction_amount, 0) and
            tx.transaction_currency == invoice.currency and
            tx.debtor_name == buyer_name
        end)

      build_previous_month_suggestion(matching_transactions, gross_value, invoice.currency)
    else
      _ -> :no_suggestion
    end
  end

  defp build_previous_month_suggestion(matching_transactions, gross_value, currency) do
    transaction_count = length(matching_transactions)

    with true <- transaction_count in 5..10,
         sum =
           Enum.reduce(
             matching_transactions,
             Decimal.new("0"),
             &Decimal.add(&1.transaction_amount, &2)
           ),
         true <- Decimal.equal?(sum, gross_value) do
      transaction_ids = Enum.map(matching_transactions, & &1.id)

      suggestion_message =
        "Znalazłem #{transaction_count} pasujących transakcji z poprzedniego miesiąca od tego samego kontrahenta — ich suma wynosi #{Money.new(currency, sum)}."

      {:ok, transaction_ids, suggestion_message}
    else
      _ -> :no_suggestion
    end
  end

  defp sales_invoice_input(%SalesInvoice{} = invoice, opts \\ []) do
    heading_level = Keyword.get(opts, :heading_level, 1)

    invoice_type =
      case invoice.invoice_type do
        :poland -> "Polska"
        :foreign -> "Zagraniczna"
      end

    """
    #{String.duplicate("#", heading_level)} Faktura sprzedażowa #{invoice.invoice_number}

    > **Opis:**

    - **Rodzaj faktury**: #{invoice_type}
    - **Nazwa kupującego**: #{invoice.buyer_display_name_label}
    - **Adres kupującego**: #{invoice.buyer_address}
    - **Data wystawienia**: #{invoice.issue_date}
    - **Data sprzedaży**: #{invoice.sale_date}
    - **Termin płatności**: #{invoice.due_date}
    - **Kwota**: #{invoice.gross_value}
    - **Waluta**: #{invoice.currency}

    > UUID: `#{invoice.id}`
    """
  end
end
