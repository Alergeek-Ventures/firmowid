defmodule Firmowid.Ash.Events.DecoderTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Ash.Union
  alias Firmowid.Ash.Events.Decoder
  alias Firmowid.Ash.Events.Payloads.InvoiceTransactionsDisconnected
  alias Firmowid.Ash.Events.TypedEvent

  test "decode/1 normalizes disconnect_all_transactions persisted as strings" do
    event_id = Ash.UUID.generate()
    record_id = Ash.UUID.generate()
    transaction_id = Ash.UUID.generate()
    matched_by = Ash.UUID.generate()

    event = %{
      id: event_id,
      record_id: record_id,
      occurred_at: ~U[2026-05-05 12:00:00.000000Z],
      resource: "Elixir.Firmowid.Ash.Invoicing.SalesInvoice",
      action: "disconnect_all_transactions",
      data: %{transaction_ids: [transaction_id]},
      metadata: %{source: "manual", matched_by: matched_by}
    }

    assert {:ok,
            %TypedEvent{
              event_id: ^event_id,
              record_id: ^record_id,
              resource: :sales_invoice,
              action: :disconnect_all_transactions,
              payload: %Union{
                type: :sales_invoice_transactions_disconnected,
                value: %InvoiceTransactionsDisconnected{} = payload
              }
            }} = Decoder.decode(event)

    assert payload.transaction_ids == [transaction_id]
    assert payload.source == :manual
    assert payload.matched_by == matched_by
  end
end
