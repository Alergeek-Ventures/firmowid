defmodule Firmowid.Ash.Assistant.InvoiceMatchingTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Assistant.Actions.Calculate
  alias Firmowid.Ash.Assistant.Actions.NormalizeToPln
  alias Firmowid.Ash.Assistant.Actions.ProposeInvoiceTransactionMatch
  alias Firmowid.Ash.Assistant.Actions.ReadCostInvoiceById
  alias Firmowid.Ash.Assistant.Actions.ReadCostInvoices
  alias Firmowid.Ash.Assistant.Actions.ReadSalesInvoiceById
  alias Firmowid.Ash.Assistant.Actions.ReadSalesInvoices
  alias Firmowid.Ash.Assistant.Actions.ReadTransactions
  alias Firmowid.Ash.Assistant.InvoiceMatching
  alias Firmowid.Ash.Assistant.InvoiceMatchingAgent
  alias Firmowid.Ash.Currencies.Converter
  alias Firmowid.Ash.Currencies.DatabaseCache
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Scope
  alias Jido.AI.Context, as: AIContext
  alias Jido.AI.ToolAdapter

  @tool_modules [
    Calculate,
    ReadTransactions,
    ReadCostInvoices,
    ReadSalesInvoices,
    NormalizeToPln,
    ProposeInvoiceTransactionMatch,
    ReadCostInvoiceById,
    ReadSalesInvoiceById
  ]

  defmodule StreamAdapter do
    @moduledoc false
    @behaviour ReqLLM.FinchRequestAdapter

    @impl true
    def call(request) do
      %{
        request
        | scheme: :http,
          host: "127.0.0.1",
          port: Application.fetch_env!(:req_llm, :assistant_test_port)
      }
    end
  end

  defmodule StreamStub do
    @moduledoc false
    def init(handler), do: handler
    def call(conn, handler), do: handler.(conn)
  end

  setup_all do
    original_converter_config = Application.get_env(:firmowid, Converter)
    Application.put_env(:firmowid, Converter, rates_provider: :api)

    on_exit(fn ->
      Application.put_env(:firmowid, Converter, original_converter_config)
    end)

    :ok
  end

  setup do
    Cachex.clear!(:currencies)

    user = admin_fixture()
    scope = scope_for(user)

    %{user: user, scope: scope}
  end

  describe "session bootstrap" do
    test "starts a deterministic assistant session with intro message", %{
      scope: scope,
      user: user
    } do
      invoice = create_cost_invoice!(user, %{invoice_identifier: unique_string("CI-FOCUSED")})
      entry_context = InvoiceMatching.entry_context_for_invoice(invoice)

      assert {:ok, session} = InvoiceMatching.start_session(scope, entry_context)

      assert session.status == :active
      assert session.title == "Dopasowanie faktury do transakcji"
      assert session.system_prompt =~ invoice.id

      assert [%{"role" => "assistant", "content" => intro_message}] = session.messages
      assert intro_message =~ "Cześć, tu Firmowid."
    end

    test "stores only focused transaction refs in transaction entry context", %{user: user} do
      transaction = create_transaction!(user, %{})

      assert InvoiceMatching.entry_context_for_transaction(transaction) == %{
               "focused_entities" => [%{type: :transaction, id: transaction.id}],
               "title" => "Dopasowanie transakcji do faktur"
             }
    end
  end

  describe "tool registration" do
    test "builds Luna streaming requests without reasoning and with application tools" do
      options = InvoiceMatchingAgent.strategy_opts()
      model = options |> Keyword.fetch!(:model) |> Jido.AI.resolve_model() |> ReqLLM.model!()
      context = ReqLLM.Context.new([ReqLLM.Context.user("test")])

      llm_options =
        options
        |> Keyword.fetch!(:llm_opts)
        |> Keyword.merge(
          api_key: "test-key",
          tools: ToolAdapter.from_actions(@tool_modules)
        )

      assert {:ok, request} =
               ReqLLM.Providers.OpenAI.attach_stream(model, context, llm_options, ReqLLM.Finch)

      body = request.body |> IO.iodata_to_binary() |> Jason.decode!()

      assert request.path == "/v1/responses"
      assert body["model"] == "gpt-6-luna"
      assert body["reasoning"]["effort"] == "none"
      assert body["stream"]
      assert Enum.any?(body["tools"], &(&1["name"] == "propose_invoice_transaction_match"))
    end

    test "registers every assistant tool on the Jido agent" do
      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: InvoiceMatchingAgent,
          initial_state: %{context: AIContext.new(system_prompt: "test")}
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal)
      end)

      Enum.each(@tool_modules, fn tool_module ->
        assert {:ok, _agent} = Jido.AI.register_tool(pid, tool_module)
      end)
    end
  end

  describe "model access propagation" do
    test "retries a model permission error without duplicating the user message", %{scope: scope} do
      counter = start_supervised!({Agent, fn -> 0 end})

      stub_assistant_stream(fn conn ->
        attempt = Agent.get_and_update(counter, fn count -> {count + 1, count + 1} end)

        if attempt == 1 do
          permission_error(conn)
        else
          response = %{
            id: "resp-retry",
            model: "gpt-6-luna",
            status: "completed",
            output: [
              %{
                id: "msg-retry",
                type: "message",
                role: "assistant",
                content: [%{type: "output_text", text: "OK"}]
              }
            ],
            usage: %{input_tokens: 10, output_tokens: 1, total_tokens: 11}
          }

          events = [
            %{
              type: "response.output_text.delta",
              item_id: "msg-retry",
              output_index: 0,
              content_index: 0,
              delta: "OK"
            },
            %{type: "response.completed", response: response}
          ]

          body =
            Enum.map_join(events, fn event ->
              "event: #{event.type}\ndata: #{Jason.encode!(event)}\n\n"
            end)

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_resp(200, body)
        end
      end)

      {:ok, session} = InvoiceMatching.start_session(scope)
      assert {:ok, updated} = InvoiceMatching.send_message(session.id, "test", scope)
      assert updated.status == :active
      assert Agent.get(counter, & &1) == 2
      assert Enum.count(updated.messages, &(&1["role"] == "user")) == 1
    end

    test "does not replay tools after a proposal has already been saved", %{
      scope: scope,
      user: user
    } do
      invoice = create_cost_invoice!(user, %{amount: Money.new!("EUR", "-50")})
      transaction = create_transaction!(user, %{})
      {:ok, session} = InvoiceMatching.start_session(scope)
      counter = start_supervised!({Agent, fn -> 0 end})

      stub_assistant_stream(fn conn ->
        Agent.update(counter, &(&1 + 1))

        assert {:ok, _} =
                 ProposeInvoiceTransactionMatch.run(
                   %{
                     message: "test",
                     transaction_ids: [transaction.id],
                     cost_invoice_ids: [invoice.id]
                   },
                   %{session_id: session.id, scope: scope}
                 )

        permission_error(conn)
      end)

      assert {:ok, updated} = InvoiceMatching.send_message(session.id, "test", scope)
      assert updated.status == :waiting_confirmation
      assert updated.pending_match.transaction_ids == [transaction.id]
      assert Agent.get(counter, & &1) == 1
    end

    test "bounds retries when access remains denied", %{scope: scope} do
      counter = start_supervised!({Agent, fn -> 0 end})

      stub_assistant_stream(fn conn ->
        Agent.update(counter, &(&1 + 1))
        permission_error(conn)
      end)

      {:ok, session} = InvoiceMatching.start_session(scope)
      assert {:error, _} = InvoiceMatching.send_message(session.id, "test", scope)
      assert Agent.get(counter, & &1) == 6
    end
  end

  describe "calculate tool" do
    test "advertises only supported arithmetic operations to the model" do
      schema =
        Calculate
        |> ToolAdapter.from_action()
        |> ReqLLM.Tool.to_json_schema()

      assert get_in(schema, ["function", "parameters", "properties", "operation", "enum"]) ==
               ["+", "-", "*", "/"]
    end

    test "performs decimal arithmetic without runtime dependencies" do
      assert {:ok, %{result: "15.5"}} =
               Calculate.run(%{numbers: ["10.5", 2, 3], operation: "+"}, %{})
    end

    test "returns a deterministic error for division by zero" do
      assert {:error, "Dzielenie przez zero"} =
               Calculate.run(%{numbers: [10, 0], operation: "/"}, %{})
    end
  end

  describe "normalize_to_pln tool" do
    test "uses seeded exchange rates instead of external APIs" do
      date = ~D[2024-01-15]

      assert :ok =
               DatabaseCache.store_historic_rates(
                 nil,
                 %{
                   "USD" => Decimal.new("1.0"),
                   "EUR" => Decimal.new("1.0"),
                   "PLN" => Decimal.new("2.0")
                 },
                 date
               )

      assert {:ok, %{result: "200"}} =
               NormalizeToPln.run(
                 %{amount: "100", currency: "EUR", date: Date.to_iso8601(date)},
                 %{}
               )
    end
  end

  describe "read transactions tool" do
    test "rejects a search without narrowing filters", %{scope: scope} do
      assert {:error, "Podaj przynajmniej jeden filtr zawężający wyszukiwanie."} =
               ReadTransactions.run(%{}, %{scope: scope})
    end

    test "returns serialized matched transactions", %{scope: scope, user: user} do
      matched_transaction =
        create_transaction!(user, %{
          creditor_name: unique_string("Assistant Matched Creditor"),
          remittance_information_unstructured: unique_string("assistant-matched"),
          amount: Money.new!("PLN", Decimal.new("123.45"))
        })

      _pending_transaction =
        create_transaction!(user, %{
          creditor_name: unique_string("Assistant Pending Creditor"),
          remittance_information_unstructured: unique_string("assistant-pending"),
          amount: Money.new!("PLN", Decimal.new("33.33"))
        })

      cost_invoice =
        create_cost_invoice!(user, %{invoice_identifier: unique_string("CI-MATCHED")})

      Ash.Seed.seed!(CostInvoiceTransaction, %{
        cost_invoice_id: cost_invoice.id,
        transaction_id: matched_transaction.id,
        organization_id: user.organization_id
      })

      assert {:ok, %{transactions: [serialized], count: 1}} =
               ReadTransactions.run(
                 %{
                   query: matched_transaction.remittance_information_unstructured,
                   reconciliation: "matched"
                 },
                 %{scope: scope}
               )

      matched_transaction = Ash.load!(matched_transaction, [:amount], scope: scope)

      assert serialized.id == matched_transaction.id
      assert serialized.creditor_name == matched_transaction.creditor_name
      assert serialized.currency == "PLN"
      assert serialized.amount == to_string(matched_transaction.amount)
    end
  end

  describe "read cost invoices tool" do
    test "returns serialized cost invoices for narrowed searches", %{scope: scope, user: user} do
      matching_identifier = unique_string("CI-ASSISTANT-COST")
      matching_invoice = create_cost_invoice!(user, %{invoice_identifier: matching_identifier})

      _other_invoice =
        create_cost_invoice!(user, %{invoice_identifier: unique_string("CI-OTHER-COST")})

      assert {:ok, %{cost_invoices: [serialized], count: 1}} =
               ReadCostInvoices.run(%{query: matching_identifier}, %{scope: scope})

      assert serialized.id == matching_invoice.id
      assert serialized.type == "cost_invoice"
      assert serialized.invoice_identifier == matching_identifier
      assert serialized.amount == %{amount: "-123.45", currency: "PLN"}
      refute Map.has_key?(serialized, :total_amount)
      refute Map.has_key?(serialized, :currency)
    end
  end

  describe "read sales invoices tool" do
    test "returns serialized sales invoices for narrowed searches", %{scope: scope, user: user} do
      matching_number = unique_string("SI-ASSISTANT-SALES")
      matching_invoice = create_sales_invoice!(user, %{invoice_number: matching_number})

      _other_invoice =
        create_sales_invoice!(user, %{invoice_number: unique_string("SI-OTHER-SALES")})

      assert {:ok, %{sales_invoices: [serialized], count: 1}} =
               ReadSalesInvoices.run(%{query: matching_number}, %{scope: scope})

      assert serialized.id == matching_invoice.id
      assert serialized.type == "sales_invoice"
      assert serialized.invoice_number == matching_number
      assert serialized.amount == %{amount: "123.0000", currency: "EUR"}
      refute Map.has_key?(serialized, :gross_value)
      refute Map.has_key?(serialized, :currency)
    end
  end

  describe "read invoice by id tools" do
    test "returns a serialized cost invoice payload", %{scope: scope, user: user} do
      invoice_identifier = unique_string("CI-BY-ID")
      invoice = create_cost_invoice!(user, %{invoice_identifier: invoice_identifier})

      assert {:ok, %{result: [serialized]}} =
               ReadCostInvoiceById.run(%{id: invoice.id}, %{scope: scope})

      assert serialized.id == invoice.id
      assert serialized.type == "cost_invoice"
      assert serialized.invoice_identifier == invoice_identifier
      assert serialized.amount == %{amount: "-123.45", currency: "PLN"}
    end

    test "returns a serialized sales invoice payload", %{scope: scope, user: user} do
      invoice_number = unique_string("SI-BY-ID")
      invoice = create_sales_invoice!(user, %{invoice_number: invoice_number})

      assert {:ok, %{result: [serialized]}} =
               ReadSalesInvoiceById.run(%{id: invoice.id}, %{scope: scope})

      assert serialized.id == invoice.id
      assert serialized.type == "sales_invoice"
      assert serialized.invoice_number == invoice_number
      assert serialized.amount == %{amount: "123.0000", currency: "EUR"}
    end
  end

  describe "propose invoice transaction match tool" do
    test "stores a pending proposal and applies it without any LLM call", %{
      scope: scope,
      user: user
    } do
      transaction =
        create_transaction!(user, %{
          creditor_name: unique_string("Assistant Proposal Creditor"),
          remittance_information_unstructured: unique_string("assistant-proposal"),
          amount: Money.new!("PLN", Decimal.new("50.00"))
        })

      cost_invoice =
        create_cost_invoice!(user, %{invoice_identifier: unique_string("CI-PROPOSAL")})

      assert {:ok, session} =
               InvoiceMatching.start_session(
                 scope,
                 InvoiceMatching.entry_context_for_invoice(cost_invoice)
               )

      message = "Proponuję połączyć tę fakturę z wybraną transakcją."

      assert {:ok,
              %{
                status: "waiting_confirmation",
                message: ^message,
                transaction_count: 1,
                invoice_count: 1
              }} =
               ProposeInvoiceTransactionMatch.run(
                 %{
                   message: message,
                   transaction_ids: [transaction.id],
                   cost_invoice_ids: [cost_invoice.id]
                 },
                 %{session_id: session.id, scope: scope}
               )

      assert {:ok, waiting_session} = Assistant.get_session(session.id, scope: scope)
      assert waiting_session.status == :waiting_confirmation
      assert waiting_session.pending_match.message == message
      assert waiting_session.pending_match.transaction_ids == [transaction.id]

      assert {:ok, _accepted_session} = InvoiceMatching.accept_pending_match(session.id, scope)

      assert {:ok, active_session} = Assistant.get_session(session.id, scope: scope)
      assert active_session.status == :active
      assert is_nil(active_session.pending_match)

      assert List.last(active_session.messages)["content"] ==
               "Połączyłem wskazane faktury z wybranymi transakcjami."

      connected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]
    end

    test "rejects a pending proposal when transaction currencies do not match", %{
      scope: scope,
      user: user
    } do
      transaction =
        create_transaction!(user, %{
          creditor_name: unique_string("Assistant Mismatch Creditor"),
          remittance_information_unstructured: unique_string("assistant-mismatch"),
          amount: Money.new!("USD", Decimal.new("50.00"))
        })

      cost_invoice =
        create_cost_invoice!(user, %{
          invoice_identifier: unique_string("CI-MISMATCH"),
          currency: "PLN"
        })

      assert {:ok, session} =
               InvoiceMatching.start_session(
                 scope,
                 InvoiceMatching.entry_context_for_invoice(cost_invoice)
               )

      message = "Proponuję połączyć tę fakturę z wybraną transakcją."

      assert {:ok, %{status: "waiting_confirmation"}} =
               ProposeInvoiceTransactionMatch.run(
                 %{
                   message: message,
                   transaction_ids: [transaction.id],
                   cost_invoice_ids: [cost_invoice.id]
                 },
                 %{session_id: session.id, scope: scope}
               )

      assert {:ok, _session} = InvoiceMatching.accept_pending_match(session.id, scope)

      connected_invoice =
        Invoicing.get_cost_invoice!(cost_invoice.id, load: [:transactions], scope: scope)

      assert Enum.map(connected_invoice.transactions, & &1.id) == [transaction.id]
    end
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.organization_id}

  defp stub_assistant_stream(handler) do
    previous_adapter = Application.get_env(:req_llm, :finch_request_adapter)
    previous_port = Application.get_env(:req_llm, :assistant_test_port)

    pid =
      start_supervised!({Bandit, plug: {StreamStub, handler}, ip: {127, 0, 0, 1}, port: 0, startup_log: false})

    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    Application.put_env(:req_llm, :finch_request_adapter, StreamAdapter)
    Application.put_env(:req_llm, :assistant_test_port, port)

    on_exit(fn ->
      if previous_adapter,
        do: Application.put_env(:req_llm, :finch_request_adapter, previous_adapter),
        else: Application.delete_env(:req_llm, :finch_request_adapter)

      if previous_port,
        do: Application.put_env(:req_llm, :assistant_test_port, previous_port),
        else: Application.delete_env(:req_llm, :assistant_test_port)
    end)
  end

  defp permission_error(conn) do
    conn
    |> Plug.Conn.put_status(403)
    |> Req.Test.json(%{
      error: %{
        code: "model_not_found",
        type: "invalid_request_error",
        message: "Project does not have access to model gpt-6-luna"
      }
    })
  end

  defp create_cost_invoice!(user, attrs) do
    invoice_attrs =
      Map.merge(
        %{
          seller: "Supplier Sp. z o.o.",
          seller_display_name: "Supplier",
          seller_address: "ul. Testowa 1, 00-001 Warszawa",
          sale_date: ~D[2026-02-01],
          issue_date: ~D[2026-02-01],
          due_date: ~D[2026-02-14],
          amount: Money.new!("PLN", "-123.45"),
          description: "Assistant test invoice",
          invoice_identifier: unique_string("CI-DEFAULT"),
          skip_invoicing: false,
          organization_id: user.organization_id
        },
        attrs
      )

    Ash.Seed.seed!(CostInvoice, invoice_attrs)
  end

  defp create_sales_invoice!(user, attrs) do
    scope = scope_for(user)

    base_attrs = %{
      invoice_type: :foreign,
      invoice_number: unique_string("SI-DEFAULT"),
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      payment_method: :transfer,
      currency: "EUR",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "DE123456789",
      buyer_full_name: "Buyer GmbH",
      buyer_address: "Teststrasse 1, 10115 Berlin",
      buyer_country: "DE",
      sales_invoice_items: [
        %{
          index: 0,
          name: "Programming service",
          quantity: Decimal.new("1"),
          unit: "szt.",
          unit_price: Decimal.new("100.00"),
          vat_rate: "23"
        }
      ]
    }

    base_attrs
    |> Map.merge(%{
      seller_nip: "1234567890",
      seller_display_name: "Seller",
      seller_address: "ul. Testowa 1"
    })
    |> Map.merge(attrs)
    |> Firmowid.InvoicingFixtures.seed_sales_invoice!(scope: scope)
  end

  defp create_transaction!(user, attrs) do
    suffix = System.unique_integer([:positive])

    Ash.Seed.seed!(
      Transaction,
      Map.merge(
        %{
          transaction_id: "TX-#{suffix}",
          internal_transaction_id: "INT-#{suffix}",
          creditor_name: "Default Creditor",
          creditor_account: "PL02114020040000300201355387",
          debtor_name: "Bytecraft",
          debtor_account: "PL61109010140000071219812874",
          amount: Money.new!("EUR", Decimal.new("-50.00")),
          booking_date: ~D[2026-01-10],
          value_date: ~D[2026-01-10],
          remittance_information_unstructured: "assistant-#{suffix}",
          bank_account_id: bank_account_fixture!(user).id,
          organization_id: user.organization_id,
          skip_invoicing: false
        },
        attrs
      )
    )
  end

  defp unique_string(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
