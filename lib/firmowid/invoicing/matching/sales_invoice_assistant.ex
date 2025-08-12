defmodule Firmowid.Invoicing.Matching.SalesInvoiceAssistant do
  @moduledoc false
  alias Firmowid.Invoicing.Matching.Assistant.CommonTools
  alias Firmowid.Invoicing.Matching.Assistant.Engine
  alias Firmowid.Invoicing.Matching.Assistant.Message
  alias Firmowid.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Invoicing.Matching.Assistant.Tool
  alias Firmowid.SalesInvoices.SalesInvoice

  @intro_message ~S"""
  Cześć, tu Firmowid!
  Żeby pomóc Ci znaleźć transakcję, potrzebuję trochę więcej informacji. Możesz wpisać je tutaj albo skorzystać z jednej z podpowiedzi poniżej.
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
          name: "link_sales_invoice_to_transaction",
          args: %{"transaction_ids" => transaction_ids, "sales_invoice_ids" => sales_invoice_ids}
        }
      } ->
        sales_invoice = sales_invoice_ids |> hd() |> Firmowid.SalesInvoices.get_sales_invoice()
        organization_id = sales_invoice.organization_id

        # todo insert_all
        for sales_invoice_id <- sales_invoice_ids, transaction_id <- transaction_ids do
          Firmowid.SalesInvoices.create_sales_invoices_transactions_connection(
            sales_invoice_id,
            transaction_id,
            organization_id
          )
        end

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

  def tools do
    [
      CommonTools.normalize_to_pln(),
      CommonTools.calculate(),
      CommonTools.search_transactions(negative: false),
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
              Firmowid.SalesInvoices.get_sales_invoice(sales_invoice_id)
            end

          transactions = Firmowid.Finances.get_transactions!(transaction_ids)

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
    to nie zawężaj parametrów wyszukiwania, np.: podając nazwę kontrahenta; jeśli użytkownik mówi
    o walucie transakcji to nie prze
    - transakcje pominięte są zwykle nieprzydatne, dlatego domyślnie nie będą przeszukiwane - natomiast
    możesz zasugerować użytkownikowi, aby rozszerzyć wyszukiwanie o pominięte transakcje
    - pominięte transakcje to takie, które już mają przyporządkowane faktury bądź nie są dokumentowane
    fakturami (jak pensje bądź podatki)
    - bądź zwięzły w wypowiedziach, użytkownik wie dokładnie jaki jest cel interakcji (zadanie), więc
    nie musisz mówić za wiele o tym, co robisz
    - nie wypisuj identyfikatorów (UUID) w wiadomościach, użytkownikowi nie są one potrzebne,
    tylko Tobie aby wykorzystać je w narzędziach
    - pierwsze wyszukiwanie transakcji powinno być tylko po datach
    - zwykle płatności następują po dacie wystawienia faktury i przed terminem płatności,

    # Dopasowujesz do tej faktury:

    #{sales_invoice_input(invoice)}
    """
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
    - **Skrócona nazwa kupującego**: #{invoice.seller_display_name}
    - **Pełna nazwa kupującego**: #{invoice.buyer_name}
    - **Adres kupującego**: #{invoice.buyer_address}
    - **Data wystawienia**: #{invoice.issue_date}
    - **Data sprzedaży**: #{invoice.sale_date}
    - **Termin płatności**: #{invoice.due_date}
    - **Kwota**: #{invoice.total_amount}
    - **Waluta**: #{invoice.currency}

    > UUID: `#{invoice.id}`
    """
  end
end
