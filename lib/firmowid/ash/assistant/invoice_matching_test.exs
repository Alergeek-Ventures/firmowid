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

  describe "calculate tool" do
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
    end

    test "returns a serialized sales invoice payload", %{scope: scope, user: user} do
      invoice_number = unique_string("SI-BY-ID")
      invoice = create_sales_invoice!(user, %{invoice_number: invoice_number})

      assert {:ok, %{result: [serialized]}} =
               ReadSalesInvoiceById.run(%{id: invoice.id}, %{scope: scope})

      assert serialized.id == invoice.id
      assert serialized.type == "sales_invoice"
      assert serialized.invoice_number == invoice_number
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

  defp create_cost_invoice!(user, attrs) do
    Ash.Seed.seed!(
      CostInvoice,
      Map.merge(
        %{
          seller: "Supplier Sp. z o.o.",
          seller_display_name: "Supplier",
          seller_address: "ul. Testowa 1, 00-001 Warszawa",
          sale_date: ~D[2026-02-01],
          issue_date: ~D[2026-02-01],
          due_date: ~D[2026-02-14],
          total_amount: Decimal.new("-123.45"),
          currency: "PLN",
          description: "Assistant test invoice",
          invoice_identifier: unique_string("CI-DEFAULT"),
          skip_invoicing: false,
          organization_id: user.organization_id
        },
        attrs
      )
    )
  end

  defp create_sales_invoice!(user, attrs) do
    base_attrs = %{
      invoice_type: :foreign,
      invoice_number: unique_string("SI-DEFAULT"),
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      payment_method: :transfer,
      currency: "EUR",
      seller_nip: "1234567890",
      seller_display_name: "Seller Sp. z o.o.",
      seller_address: "ul. Testowa 1, 00-001 Warszawa",
      seller_account_number: "12345678901234567890123456",
      buyer_type: :company,
      buyer_id: "DE123456789",
      buyer_full_name: "Buyer GmbH",
      buyer_address: "Teststrasse 1, 10115 Berlin",
      buyer_country: "DE",
      ksef_invoice_kind: :vat,
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

    Invoicing.create_sales_invoice!(Map.merge(base_attrs, attrs), scope: scope_for(user))
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
