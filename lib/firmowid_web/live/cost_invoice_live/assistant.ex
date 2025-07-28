defmodule FirmowidWeb.CostInvoiceLive.Assistant do
  use FirmowidWeb, :live_component

  alias Firmowid.Invoicing.Matching.Assistant
  alias Firmowid.Invoicing.Matching.Assistant.MessagesStorage
  alias FirmowidWeb.Helpers.TimeFormatter
  alias Firmowid.Finances
  alias Firmowid.Accounts
  alias Firmowid.Invoicing.Matching.Assistant.Message

  @impl true
  def update(%{event: {:loading, boolean}}, socket) do
    {:ok, assign(socket, :loading, boolean)}
  end

  def update(%{event: %Message{role: role} = msg}, socket)
      when role in [:function_call, :function_result] and
             msg.payload.name in ["link_cost_invoice_to_transaction", "search_transactions"] do
    socket =
      case msg do
        %Message{
          role: :function_call,
          payload: %{
            name: "link_cost_invoice_to_transaction",
            done: true
          }
        } ->
          transactions = Finances.get_transactions!(msg.payload.args["transaction_ids"])
          msg = Map.put(msg, :transactions, transactions)

          socket
          |> assign(:waiting_for_decision, true)
          |> stream_insert(:messages, msg)

        %Message{
          role: :function_call,
          payload: %{name: "link_cost_invoice_to_transaction", done: false}
        } ->
          socket

        _ ->
          stream_insert(socket, :messages, msg)
      end

    {:ok, socket}
  end

  def update(%{event: %Message{role: role} = msg}, socket) when role in [:user, :assistant] do
    {:ok, stream_insert(socket, :messages, msg)}
  end

  def update(%{event: %Message{}}, socket), do: {:ok, socket}

  # pseudo mount
  def update(%{invoice: invoice, current_user: current_user}, socket) do
    Bodyguard.permit!(Firmowid.CostInvoices, :show, current_user, invoice)
    conversation_id = Assistant.start_conversation(invoice)

    # messages = [
    #   %Firmowid.Invoicing.Matching.Assistant.Message{
    #     id: "01981407-1c2b-7d8f-9cae-2449529b10ae",
    #     role: :assistant,
    #     text: ~S"""
    #     Cześć, tu Firmowid!
    #     Żeby pomóc Ci znaleźć transakcję, potrzebuję trochę więcej informacji. Możesz wpisać je tutaj albo skorzystać z jednej z podpowiedzi poniżej.
    #     """,
    #     payload: nil,
    #     timestamp: ~U[2025-07-16 16:17:48.092381Z]
    #   },
    #   %Firmowid.Invoicing.Matching.Assistant.Message{
    #     id: "01981407-1c2b-7d8f-9cae-2449529b103e",
    #     role: :user,
    #     text: "to faktura zbiorcza za wszystkie transakcje z poprzedniego miesiąca",
    #     payload: nil,
    #     timestamp: ~U[2025-07-16 16:17:48.092381Z]
    #   },
    #   %Firmowid.Invoicing.Matching.Assistant.Message{
    #     id: "01981407-203c-7bd5-b36d-14d621ab8e24",
    #     role: :function_call,
    #     text:
    #       "search_transactions(%{\"filters\" => %{\"currency\" => \"PLN\", \"date_from\" => \"2025-02-01\", \"date_to\" => \"2025-02-28\", \"only_unmatched\" => true}})",
    #     payload: %{
    #       args: %{
    #         "filters" => %{
    #           "currency" => "PLN",
    #           "date_from" => "2025-02-01",
    #           "date_to" => "2025-02-28",
    #           "amount_gt" => "0.00",
    #           "amount_lt" => "1000.00",
    #           "only_unmatched" => false,
    #           "query" => "fasdfads"
    #         }
    #       },
    #       name: "search_transactions"
    #     },
    #     timestamp: ~U[2025-07-16 16:17:48.092381Z]
    #   },
    #   %Firmowid.Invoicing.Matching.Assistant.Message{
    #     id: "01981407-203c-7bd5-b36d-14d621ab8e2d",
    #     role: :function_call,
    #     text:
    #       "search_transactions(%{\"filters\" => %{\"currency\" => \"PLN\", \"date_from\" => \"2025-02-01\", \"date_to\" => \"2025-02-28\", \"only_unmatched\" => true}})",
    #     payload: %{
    #       args: %{
    #         "filters" => %{}
    #       },
    #       name: "search_transactions"
    #     },
    #     timestamp: ~U[2025-07-16 16:17:48.092381Z]
    #   },
    #   %Firmowid.Invoicing.Matching.Assistant.Message{
    #     id: "01981407-204a-774f-be7a-d717c078ce61",
    #     role: :function_result,
    #     text:
    #       "## Transakcja\n\n> **Dodatkowe informacje z banku:** Nr karty ...9285 25,00PLN\n\n- **Data księgowania:** 2025-02-22\n- **Data wartości:** 2025-02-19\n- **Kwota:** -25.00\n- **Waluta:** PLN\n- **Odbiorca:** ALERGEEK VENTURES SPÓŁKA Z OG\n- **Numer konta odbiorcy:** N/A\n- **Nadawca:** www.mobileviking.pl Wroclaw\n- **Numer konta nadawcy:** N/A\n- **Powiązane faktury kosztowe:** \n\n> UUID: 0195379d-eee5-727d-a663-2f2488fd6c58\n\n\n## Transakcja\n\n> **Dodatkowe informacje z banku:** Nr karty ...9285 10,00PLN\n\n- **Data księgowania:** 2025-02-12\n- **Data wartości:** 2025-02-09\n- **Kwota:** -10.00\n- **Waluta:** PLN\n- **Odbiorca:** ALERGEEK VENTURES SPÓŁKA Z OG\n- **Numer konta odbiorcy:** N/A\n- **Nadawca:** www.mobileviking.pl Wroclaw\n- **Numer konta nadawcy:** N/A\n- **Powiązane faktury kosztowe:** \n\n> UUID: 0195041e-2591-7db4-81ca-360f00c4c651\n\n\n## Transakcja\n\n> **Dodatkowe informacje z banku:** Nr karty ...9285 50,00PLN\n\n- **Data księgowania:** 2025-02-10\n- **Data wartości:** 2025-02-07\n- **Kwota:** -50.00\n- **Waluta:** PLN\n- **Odbiorca:** ALERGEEK VENTURES SPÓŁKA Z OG\n- **Numer konta odbiorcy:** N/A\n- **Nadawca:** www.mobileviking.pl Wroclaw\n- **Numer konta nadawcy:** N/A\n- **Powiązane faktury kosztowe:** \n\n> UUID: 0195041e-2591-7d0c-be2f-aa094f38ee9a\n\n\n## Transakcja\n\n> **Dodatkowe informacje z banku:** Nr karty ...9285 25,00PLN\n\n- **Data księgowania:** 2025-02-09\n- **Data wartości:** 2025-02-06\n- **Kwota:** -25.00\n- **Waluta:** PLN\n- **Odbiorca:** ALERGEEK VENTURES SPÓŁKA Z OG\n- **Numer konta odbiorcy:** N/A\n- **Nadawca:** www.mobileviking.pl Wroclaw\n- **Numer konta nadawcy:** N/A\n- **Powiązane faktury kosztowe:** \n\n> UUID: 0194ef85-280f-72dd-8dc2-8873c530605b\n\n\n## Transakcja\n\n> **Dodatkowe informacje z banku:** Nr karty ...9285 16,00PLN\n\n- **Data księgowania:** 2025-02-09\n- **Data wartości:** 2025-02-06\n- **Kwota:** -16.00\n- **Waluta:** PLN\n- **Odbiorca:** ALERGEEK VENTURES SPÓŁKA Z OG\n- **Numer konta odbiorcy:** N/A\n- **Nadawca:** www.mobileviking.pl Wroclaw\n- **Numer konta nadawcy:** N/A\n- **Powiązane faktury kosztowe:** \n\n> UUID: 0194ef85-280f-75a7-8d12-145772e6dcfe\n",
    #     payload: %{
    #       args: %{
    #         "filters" => %{
    #           "currency" => "PLN",
    #           "date_from" => "2025-02-01",
    #           "date_to" => "2025-02-28",
    #           "only_unmatched" => true
    #         }
    #       },
    #       name: "search_transactions",
    #       result: [
    #         %Firmowid.Finances.Transaction{
    #           id: "0195379d-eee5-727d-a663-2f2488fd6c58",
    #           transaction_id: "AT#561164105",
    #           internal_transaction_id: "58b45609e06837602f718c5787d26529",
    #           creditor_name: "www.mobileviking.pl Wroclaw",
    #           creditor_account: "N/A",
    #           debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #           debtor_account: "N/A",
    #           transaction_amount: Decimal.new("-25.00"),
    #           transaction_currency: "PLN",
    #           booking_date: ~D[2025-02-22],
    #           value_date: ~D[2025-02-19],
    #           remittance_information_unstructured: "Nr karty  ...9285 25,00PLN",
    #           skip_invoicing: false,
    #           bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #           bank_account: nil,
    #           cost_invoices_transactions: [],
    #           sales_invoices_transactions: [],
    #           organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #           organization: nil,
    #           inserted_at: ~U[2025-02-24 11:00:52Z],
    #           updated_at: ~U[2025-05-20 11:00:37Z]
    #         },
    #         %Firmowid.Finances.Transaction{
    #           id: "0195041e-2591-7db4-81ca-360f00c4c651",
    #           transaction_id: "AT#559040150",
    #           internal_transaction_id: "1cd5cc42967f946b1f6c1b052bca0cbd",
    #           creditor_name: "www.mobileviking.pl Wroclaw",
    #           creditor_account: "N/A",
    #           debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #           debtor_account: "N/A",
    #           transaction_amount: Decimal.new("-10.00"),
    #           transaction_currency: "PLN",
    #           booking_date: ~D[2025-02-12],
    #           value_date: ~D[2025-02-09],
    #           remittance_information_unstructured: "Nr karty  ...9285 10,00PLN",
    #           skip_invoicing: false,
    #           bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #           bank_account: nil,
    #           cost_invoices_transactions: [],
    #           sales_invoices_transactions: [],
    #           organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #           organization: nil,
    #           inserted_at: ~U[2025-02-14 11:00:39Z],
    #           updated_at: ~U[2025-05-12 11:00:33Z]
    #         },
    #         %Firmowid.Finances.Transaction{
    #           id: "0195041e-2591-7d0c-be2f-aa094f38ee9a",
    #           transaction_id: "AT#558562705",
    #           internal_transaction_id: "4401bbdb885cbd5d77ac9e7b55419226",
    #           creditor_name: "www.mobileviking.pl Wroclaw",
    #           creditor_account: "N/A",
    #           debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #           debtor_account: "N/A",
    #           transaction_amount: Decimal.new("-50.00"),
    #           transaction_currency: "PLN",
    #           booking_date: ~D[2025-02-10],
    #           value_date: ~D[2025-02-07],
    #           remittance_information_unstructured: "Nr karty  ...9285 50,00PLN",
    #           skip_invoicing: false,
    #           bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #           bank_account: nil,
    #           cost_invoices_transactions: [],
    #           sales_invoices_transactions: [],
    #           organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #           organization: nil,
    #           inserted_at: ~U[2025-02-14 11:00:39Z],
    #           updated_at: ~U[2025-04-29 11:01:37Z]
    #         },
    #         %Firmowid.Finances.Transaction{
    #           id: "0194ef85-280f-72dd-8dc2-8873c530605b",
    #           transaction_id: "AT#558247778",
    #           internal_transaction_id: "a7ba3c4f5cb22887c1b24d91090854a1",
    #           creditor_name: "www.mobileviking.pl Wroclaw",
    #           creditor_account: "N/A",
    #           debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #           debtor_account: "N/A",
    #           transaction_amount: Decimal.new("-25.00"),
    #           transaction_currency: "PLN",
    #           booking_date: ~D[2025-02-09],
    #           value_date: ~D[2025-02-06],
    #           remittance_information_unstructured: "Nr karty  ...9285 25,00PLN",
    #           skip_invoicing: false,
    #           bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #           bank_account: nil,
    #           cost_invoices_transactions: [],
    #           sales_invoices_transactions: [],
    #           organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #           organization: nil,
    #           inserted_at: ~U[2025-02-10 11:01:08Z],
    #           updated_at: ~U[2025-04-29 11:01:37Z]
    #         },
    #         %Firmowid.Finances.Transaction{
    #           id: "0194ef85-280f-75a7-8d12-145772e6dcfe",
    #           transaction_id: "AT#558247777",
    #           internal_transaction_id: "2b1fd5fb1fe7007e1d097ab7797243ea",
    #           creditor_name: "www.mobileviking.pl Wroclaw",
    #           creditor_account: "N/A",
    #           debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #           debtor_account: "N/A",
    #           transaction_amount: Decimal.new("-16.00"),
    #           transaction_currency: "PLN",
    #           booking_date: ~D[2025-02-09],
    #           value_date: ~D[2025-02-06],
    #           remittance_information_unstructured: "Nr karty  ...9285 16,00PLN",
    #           skip_invoicing: false,
    #           bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #           bank_account: nil,
    #           cost_invoices_transactions: [],
    #           sales_invoices_transactions: [],
    #           organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #           organization: nil,
    #           inserted_at: ~U[2025-02-10 11:01:08Z],
    #           updated_at: ~U[2025-04-29 11:01:37Z]
    #         }
    #       ]
    #     },
    #     timestamp: ~U[2025-07-16 16:17:48.106296Z]
    #   },
    #   %{
    #     id: "019817ec-07ec-71c3-b55e-c063a21d855b",
    #     timestamp: ~U[2025-07-17 10:26:41.260522Z],
    #     text:
    #       "link_cost_invoice_to_transaction(%{\"cost_invoice_ids\" => [\"01957157-c00d-7433-bd41-3d8b719610a4\"], \"transaction_ids\" => [\"0195379d-eee5-727d-a663-2f2488fd6c58\", \"0195041e-2591-7db4-81ca-360f00c4c651\", \"0195041e-2591-7d0c-be2f-aa094f38ee9a\", \"0194ef85-280f-72dd-8dc2-8873c530605b\", \"0194ef85-280f-75a7-8d12-145772e6dcfe\"]})",
    #     role: :function_call,
    #     payload: %{
    #       args: %{
    #         "cost_invoice_ids" => ["01957157-c00d-7433-bd41-3d8b719610a4"],
    #         "transaction_ids" => [
    #           "0195379d-eee5-727d-a663-2f2488fd6c58",
    #           "0195041e-2591-7db4-81ca-360f00c4c651",
    #           "0195041e-2591-7d0c-be2f-aa094f38ee9a",
    #           "0194ef85-280f-72dd-8dc2-8873c530605b",
    #           "0194ef85-280f-75a7-8d12-145772e6dcfe"
    #         ],
    #         "message" =>
    #           "Znalazłem 2 pasujące transakcje - ich suma wynosi 80,00 PLN co jest bliskie kwocie na fakturze:"
    #       },
    #       name: "link_cost_invoice_to_transaction"
    #     },
    #     transactions: [
    #       %{
    #         id: "0194ef85-280f-72dd-8dc2-8873c530605b",
    #         organization: nil,
    #         organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #         transaction_id: "AT#558247778",
    #         internal_transaction_id: "a7ba3c4f5cb22887c1b24d91090854a1",
    #         creditor_name: "www.mobileviking.pl Wroclaw",
    #         creditor_account: "N/A",
    #         debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #         debtor_account: "N/A",
    #         transaction_amount: Decimal.new("-25.00"),
    #         transaction_currency: "PLN",
    #         booking_date: ~D[2025-02-09],
    #         value_date: ~D[2025-02-06],
    #         remittance_information_unstructured: "Nr karty  ...9285 25,00PLN",
    #         skip_invoicing: false,
    #         bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #         bank_account: nil,
    #         cost_invoices_transactions: nil,
    #         sales_invoices_transactions: nil,
    #         inserted_at: ~U[2025-02-10 11:01:08Z],
    #         updated_at: ~U[2025-04-29 11:01:37Z],
    #         amount: Money.new(:PLN, "-25.00")
    #       },
    #       %{
    #         id: "0194ef85-280f-75a7-8d12-145772e6dcfe",
    #         organization: nil,
    #         organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #         transaction_id: "AT#558247777",
    #         internal_transaction_id: "2b1fd5fb1fe7007e1d097ab7797243ea",
    #         creditor_name: "www.mobileviking.pl Wroclaw",
    #         creditor_account: "N/A",
    #         debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #         debtor_account: "N/A",
    #         transaction_amount: Decimal.new("-16.00"),
    #         transaction_currency: "PLN",
    #         booking_date: ~D[2025-02-09],
    #         value_date: ~D[2025-02-06],
    #         remittance_information_unstructured: "Nr karty  ...9285 16,00PLN",
    #         skip_invoicing: false,
    #         bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #         bank_account: nil,
    #         cost_invoices_transactions: nil,
    #         sales_invoices_transactions: nil,
    #         inserted_at: ~U[2025-02-10 11:01:08Z],
    #         updated_at: ~U[2025-04-29 11:01:37Z],
    #         amount: Money.new(:PLN, "-16.00")
    #       },
    #       %{
    #         id: "0195041e-2591-7d0c-be2f-aa094f38ee9a",
    #         organization: nil,
    #         organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #         transaction_id: "AT#558562705",
    #         internal_transaction_id: "4401bbdb885cbd5d77ac9e7b55419226",
    #         creditor_name: "www.mobileviking.pl Wroclaw",
    #         creditor_account: "N/A",
    #         debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #         debtor_account: "N/A",
    #         transaction_amount: Decimal.new("-50.00"),
    #         transaction_currency: "PLN",
    #         booking_date: ~D[2025-02-10],
    #         value_date: ~D[2025-02-07],
    #         remittance_information_unstructured: "Nr karty  ...9285 50,00PLN",
    #         skip_invoicing: false,
    #         bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #         bank_account: nil,
    #         cost_invoices_transactions: nil,
    #         sales_invoices_transactions: nil,
    #         inserted_at: ~U[2025-02-14 11:00:39Z],
    #         updated_at: ~U[2025-04-29 11:01:37Z],
    #         amount: Money.new(:PLN, "-50.00")
    #       },
    #       %{
    #         id: "0195041e-2591-7db4-81ca-360f00c4c651",
    #         organization: nil,
    #         organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #         transaction_id: "AT#559040150",
    #         internal_transaction_id: "1cd5cc42967f946b1f6c1b052bca0cbd",
    #         creditor_name: "www.mobileviking.pl Wroclaw",
    #         creditor_account: "N/A",
    #         debtor_name: "ALERGEEK VENTURES SPÓŁKA Z OG",
    #         debtor_account: "N/A",
    #         transaction_amount: Decimal.new("-10.00"),
    #         transaction_currency: "PLN",
    #         booking_date: ~D[2025-02-12],
    #         value_date: ~D[2025-02-09],
    #         remittance_information_unstructured: "Nr karty  ...9285 10,00PLN",
    #         skip_invoicing: false,
    #         bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #         bank_account: nil,
    #         cost_invoices_transactions: nil,
    #         sales_invoices_transactions: nil,
    #         inserted_at: ~U[2025-02-14 11:00:39Z],
    #         updated_at: ~U[2025-05-12 11:00:33Z],
    #         amount: Money.new(:PLN, "-10.00")
    #       },
    #       %{
    #         id: "0195379d-eee5-727d-a663-2f2488fd6c58",
    #         organization: nil,
    #         organization_id: "01980e88-c7b9-7bff-8975-17f3e3214b74",
    #         transaction_id: "AT#561164105",
    #         internal_transaction_id: "58b45609e06837602f718c5787d26529",
    #         creditor_name:
    #           "www.mobileviking.pl Wroclawfshfjashjfajshgfjhsajfjkahjkfhakjhfdhaskdjhfkjashdkj",
    #         creditor_account: "N/A",
    #         debtor_name: "ALERGEEK VENTURES SPÓŁКА Z OG",
    #         debtor_account: "N/A",
    #         transaction_amount: Decimal.new("-25.00"),
    #         transaction_currency: "PLN",
    #         booking_date: ~D[2025-02-22],
    #         value_date: ~D[2025-02-19],
    #         remittance_information_unstructured: "Nr karty  ...9285 25,00PLN",
    #         skip_invoicing: false,
    #         bank_account_id: "01948dfe-51cd-785e-afa6-15e33dec8e43",
    #         bank_account: nil,
    #         cost_invoices_transactions: nil,
    #         sales_invoices_transactions: nil,
    #         inserted_at: ~U[2025-02-24 11:00:52Z],
    #         updated_at: ~U[2025-05-20 11:00:37Z],
    #         amount: Money.new(:PLN, "-25.00")
    #       }
    #     ]
    #   }
    # ]

    messages = MessagesStorage.get(conversation_id)

    socket =
      socket
      |> assign(:conversation_id, conversation_id)
      |> assign(:invoice_id, invoice.id)
      |> assign(:input, "")
      |> assign(:loading, false)
      |> stream(:messages, messages)
      |> assign(:waiting_for_decision, false)
      |> assign(:zero_state, true)
      |> assign(:current_user, current_user |> Accounts.get_user_with_avatar())

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"message" => message}, socket) do
    Assistant.send_message_streaming(socket.assigns.conversation_id, message)

    socket =
      socket
      |> assign(:input, "")
      |> assign(:zero_state, false)

    {:noreply, socket}
  end

  def handle_event("accept", _params, socket) do
    invoice = Firmowid.CostInvoices.get_cost_invoice!(socket.assigns.invoice_id)

    Bodyguard.permit!(
      Firmowid.CostInvoices,
      :update,
      socket.assigns.current_user,
      invoice
    )

    Assistant.accept_linking(socket.assigns.conversation_id)

    # TODO: convert into reinitialization of the cost_invoice liveview
    Process.sleep(500)

    socket =
      socket
      |> LiveToast.put_toast(:success, "Transakcje zostały dopasowane do faktury")
      |> push_navigate(to: ~p"/kosztowe/#{socket.assigns.invoice_id}")

    {:noreply, socket}
  end

  def handle_event("reject", _params, socket) do
    Assistant.reject_linking(socket.assigns.conversation_id)

    {:noreply,
     socket
     |> assign(:input, "")
     |> assign(:waiting_for_decision, false)}
  end

  # New rendering for Message struct with payload
  @doc """
  Renders a message based on its role and payload. Supports user, assistant, function_call, and function_result.
  """
  def message(%{role: :user, text: text}, _myself, opts) do
    current_user = Keyword.fetch!(opts, :current_user)
    assigns = %{text: text, current_user: current_user}

    ~H"""
    <div class="flex flex-row gap-3 justify-end">
      <p class="px-4 py-2 bg-grey-200 rounded max-w-2xl">{@text}</p>
      <div class="w-10 h-10">
        <.avatar class="size-10">
          <.avatar_image src={@current_user.avatar_url} alt="Avatar" />
          <.avatar_fallback>
            {String.slice(@current_user.email, 0, 1) |> String.upcase()}
          </.avatar_fallback>
        </.avatar>
      </div>
    </div>
    """
  end

  def message(%{role: :assistant, text: text}, _myself, _opts) do
    assigns = %{text: text}

    ~H"""
    <div class="flex flex-row gap-3">
      <img src="/images/logo_firmowid.png" class="w-10 h-10 mt-2" />
      <div class="prose prose-p:p-2 prose-p:text-black prose-p:whitespace-pre-wrap max-w-2xl">
        {render_content(@text)}
      </div>
    </div>
    """
  end

  def message(
        %{
          role: :function_call,
          payload: %{name: "search_transactions", args: args}
        },
        _myself,
        _opts
      ) do
    filters =
      Map.get(args, "filters", %{})
      |> Map.put_new("date_from", nil)
      |> Map.put_new("date_to", nil)
      |> Map.put_new("amount_gt", nil)
      |> Map.put_new("amount_lt", nil)
      |> Map.put_new("currency", nil)
      |> Map.put_new("only_unmatched", true)
      |> Map.put_new("query", nil)

    date_filter =
      [
        if(filters["date_from"], do: "od #{TimeFormatter.format_date(filters["date_from"])}"),
        if(filters["date_to"], do: "do #{TimeFormatter.format_date(filters["date_to"])}")
      ]
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        list -> Enum.join(list, " ")
      end

    amount_filter =
      [filters["amount_gt"], filters["amount_lt"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" - ")

    assigns = %{filters: filters, date_filter: date_filter, amount_filter: amount_filter}

    ~H"""
    <div class="flex flex-row gap-2 items-center ml-[52px] py-2 px-4 flex-wrap max-w-2xl min-h-8 box-content">
      <p class="text-sm text-nowrap leading-none">Szukam transakcji</p>
      <div
        :if={@date_filter}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        data: <span class="font-semibold">{@date_filter}</span>
      </div>
      <div
        :if={@amount_filter != ""}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        kwota: <span class="font-semibold">{@amount_filter}</span>
      </div>
      <div
        :if={@filters["currency"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        waluta: <span class="font-semibold">{@filters["currency"]}</span>
      </div>
      <div
        :if={@filters["query"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        fraza: <span class="font-semibold">{@filters["query"]}</span>
      </div>
      <div
        :if={not @filters["only_unmatched"]}
        class="py-1 px-3 bg-orange-100 text-orange-900 rounded whitespace-nowrap animate-fade-in"
      >
        również dopasowane
      </div>
    </div>
    """
  end

  def message(
        %{
          role: :function_call,
          payload: %{
            name: "link_cost_invoice_to_transaction",
            args: %{"message" => assistant_message}
          },
          transactions: transactions
        } = message,
        myself,
        _opts
      ) do
    assigns = %{
      id: message.id,
      message: assistant_message,
      transactions: transactions,
      myself: myself
    }

    ~H"""
    <div class="ml-[52px] py-2 px-4 max-w-2xl -mt-12 flex flex-col gap-6">
      <p>{@message}</p>

      <ul class="gap-2 flex flex-col w-full">
        <li
          :for={transaction <- @transactions}
          class="py-1 px-3 flex flex-row gap-4 justify-between items-start bg-grey-50 rounded"
        >
          <div class="grid grid-cols-[min-content,1fr] gap-x-3">
            <span class="text-sm text-grey-700">Nadawca</span>
            <span class="text-black truncate">{transaction.creditor_name}</span>
            <span class="text-sm text-grey-700">Zaksięgowano</span>
            <span class="text-black">{TimeFormatter.format_date(transaction.booking_date)}</span>
          </div>
          <div class="flex flex-row gap-3 items-center">
            {transaction.amount}
            <.icon name="hero-credit-card-micro" class="text-grey-700" />
          </div>
        </li>
      </ul>
    </div>
    """
  end

  def message(%{role: :function_call, payload: %{name: name, args: args}}, _myself, _opts) do
    assigns = %{name: name, args: args}

    ~H"""
    <div class="flex flex-row gap-4 items-center">
      <div>🛠️ <b>{@name}</b> called</div>
      <div><pre>{inspect(@args)}</pre></div>
    </div>
    """
  end

  def message(
        %{role: :function_result, payload: %{name: name, result: result}},
        _myself,
        _opts
      ) do
    assigns = %{name: name, result: result}

    case {name, result} do
      {"search_transactions", list} when is_list(list) ->
        text =
          case length(list) do
            0 -> "Nie znalazłem żadnych transakcji"
            1 -> "Znalazłem 1 transakcję"
            count when count < 5 -> "Znalazłem #{count} transakcje"
            count -> "Znalazłem #{count} transakcji"
          end

        assigns = Map.put(assigns, :text, text)

        ~H"""
        <div class="flex flex-row gap-2 items-center ml-[52px] py-2 px-4 flex-wrap -mt-12">
          <p class="text-sm">{@text}</p>
        </div>
        """

      _ ->
        ~H"""
        <div class="flex flex-row gap-4 items-center">
          <div>🛠️ <b>{@name}</b> result</div>
          <div><pre>{inspect(@result)}</pre></div>
        </div>
        """
    end
  end

  # fallback for unknown roles
  def message(%{role: role, text: text, payload: payload}, _myself, _opts) do
    assigns = %{role: role, text: text, payload: payload}

    ~H"""
    <div>[{to_string(@role)}] {render_content(@text)} {inspect(@payload)}</div>
    """
  end

  def message(%{type: _} = assigns, _myself, _opts) do
    ~H"""
    <div>[{to_string(@type)}] {render_content(@content)} {inspect(@metadata)}</div>
    """
  end

  def render_content(nil), do: "failed to render content"

  def render_content(content) do
    content |> MDEx.to_html!() |> raw()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="assistant-chat relative flex flex-col mx-auto w-full h-full">
      <button
        id="chat-close-button"
        phx-hook="Tippy"
        data-tippy-content="Zamknij czat"
        phx-click="close_chat"
        phx-target="#cost-invoice-show"
        class={[
          "text-sm text-grey-700 self-end flex items-center gap-2 hover:text-grey-400 transition-colors mb-4",
          "absolute top-0 right-0 bg-lightGreyBg hover:border-grey-400 border border-transparent rounded p-2 z-10"
        ]}
      >
        <.icon name="hero-x-mark-mini" />
      </button>
      <div
        class="flex flex-col flex-grow gap-12 py-4 pr-4 overflow-y-auto"
        id="messages"
        phx-update="stream"
        phx-hook="ScrollToBottom"
      >
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {message(msg, @myself, current_user: @current_user)}
        </div>
        <%= if @zero_state do %>
          <div class="flex flex-row flex-wrap gap-3 items-center justify-center py-4">
            <%= for possible_message <- [
            "Ta faktura pokrywa wszystkie transakcje z poprzedniego miesiąca",
            "Transakcja za tę fakturę ma inną nazwę kontrahenta",
            "Opłata została wykonana znacznie później niż faktura została wystawiona",
          ] do %>
              <.button
                phx-click="send"
                color="orange"
                class="text-sm text-orangeText bg-orangeBg font-bold hover:text-orangeBg hover:bg-orangeText"
                phx-target={@myself}
                phx-value-message={possible_message}
              >
                {possible_message}
              </.button>
            <% end %>
          </div>
        <% end %>
      </div>

      <form
        :if={not @waiting_for_decision}
        class="flex flex-row gap-2 border border-grey-300 h-12 py-2 px-4 mx-16 mb-8 rounded-md bg-white"
        phx-submit="send"
        phx-target={@myself}
      >
        <input
          name="message"
          value={@input}
          autocomplete="off"
          placeholder={if @loading, do: "Firmowid myśli...", else: "Napisz swoją wiadomość"}
          disabled={@loading}
          class={[
            "placeholder:text-grey-400 text-black w-full p-0 border-none focus:ring-0",
            "focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
        />
        <button
          type="submit"
          disabled={@loading}
          class="text-grey-400 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <%= if @loading do %>
            <.icon name="hero-arrow-path" class="animate-spin" />
          <% else %>
            <.icon name="hero-paper-airplane" />
          <% end %>
        </button>
      </form>

      <div :if={@waiting_for_decision} class="flex flex-col gap-3 items-center mb-8">
        <p>Połączyć te transakcje z fakturą?</p>
        <div class="grid grid-cols-2 gap-3">
          <.button
            phx-click="reject"
            phx-target={@myself}
            color="light_grey"
            variant="outline"
            class="text-nowrap"
          >
            Szukaj dalej
          </.button>
          <.button phx-click="accept" phx-target={@myself} color="orange">
            Zatwierdź
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
