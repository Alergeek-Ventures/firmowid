defmodule Firmowid.Ash.Invoicing.Matching.SalesInvoiceAssistantTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Ash.Invoicing.Matching.SalesInvoiceAssistant
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  test "S08 deterministic aggregate suggestion is accepted and marks invoice as matched" do
    admin = admin_fixture()

    scope = %Scope{
      actor: %SystemActor{org_id: admin.organization_id, role: :admin},
      tenant: admin.organization_id
    }

    {:ok, invoice} =
      SalesInvoice.create(
        %{
          invoice_type: :poland,
          invoice_number: "S08/FV/#{System.unique_integer([:positive])}",
          issue_date: Date.utc_today(),
          sale_date: Date.utc_today(),
          due_date: Date.add(Date.utc_today(), 14),
          payment_method: :transfer,
          currency: "PLN",
          seller_nip: "6161525811",
          seller_display_name: "Bytecraft Collective sp. z o.o.",
          seller_address: "ul. Marszałkowska 11/4, 00-624 Warszawa",
          seller_account_number: "PL61105000997603123456789012",
          buyer_type: :company,
          buyer_id: "1111111111",
          buyer_full_name: "Aurora Retail Sp. z o.o.",
          buyer_display_name: "Aurora Retail Sp. z o.o.",
          buyer_address: "ul. Handlowa 12, 00-950 Warszawa",
          buyer_country: "PL",
          ksef_invoice_kind: :vat,
          sales_invoice_items: [
            %{
              index: 0,
              name: "Pakiet wdrożeniowy",
              quantity: Decimal.new("1"),
              unit: "szt",
              unit_price: Decimal.new("1000.00"),
              vat_rate: "23"
            }
          ]
        },
        tenant: admin.organization_id,
        actor: admin,
        authorize?: false
      )

    prev_month = Date.shift(Date.utc_today(), month: -1)

    [250.00, 300.00, 180.00, 200.00, 300.00]
    |> Enum.with_index(1)
    |> Enum.each(fn {amount, idx} ->
      Ash.Seed.seed!(Transaction, %{
        transaction_id: "S08-TX-#{System.unique_integer([:positive])}",
        internal_transaction_id: "S08-INT-TX-#{System.unique_integer([:positive])}",
        creditor_name: "Bytecraft Collective sp. z o.o.",
        creditor_account: "PL61105000997603123456789012",
        debtor_name: "Aurora Retail Sp. z o.o.",
        debtor_account: "PL95109010140000071219812874",
        transaction_amount: Decimal.new("#{amount}"),
        transaction_currency: "PLN",
        booking_date: Date.new!(prev_month.year, prev_month.month, 2 + idx),
        value_date: Date.new!(prev_month.year, prev_month.month, 2 + idx),
        remittance_information_unstructured: "Aurora Retail — płatność częściowa #{idx}/5",
        organization_id: admin.organization_id,
        skip_invoicing: false
      })
    end)

    conversation_id = SalesInvoiceAssistant.start_conversation(invoice, scope)

    :ok =
      SalesInvoiceAssistant.send_message_streaming(
        conversation_id,
        "Ta faktura pokrywa wszystkie transakcje z poprzedniego miesiąca"
      )

    assert_receive %{role: :user}, 1_000

    assert_receive %{role: :function_call, payload: %{name: "link_sales_invoice_to_transaction"}},
                   1_000

    latest = MessagesStorage.get_latest(conversation_id)
    assert latest.role == :function_call
    assert latest.payload.name == "link_sales_invoice_to_transaction"

    tx_ids = latest.payload.args["transaction_ids"]
    assert length(tx_ids) == 5

    :ok = SalesInvoiceAssistant.accept_linking(conversation_id)

    refreshed = Invoicing.get_sales_invoice!(invoice.id, load: [:transactions], scope: scope)
    assert length(refreshed.transactions) == 5

    matched =
      Invoicing.list_sales_invoices!(%{reconciliation: :matched, ids: [invoice.id]}, scope: scope)

    assert length(matched) == 1
  end
end
