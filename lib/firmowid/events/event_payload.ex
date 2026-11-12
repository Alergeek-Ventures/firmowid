defmodule Firmowid.Events.EventPayload do
  @moduledoc """
  Union of all typed event-family payloads stored in `ash_events`.
  """

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        cost_invoice_transactions_connected: [
          type: Firmowid.Events.Payloads.InvoiceTransactionsConnected
        ],
        cost_invoice_transactions_disconnected: [
          type: Firmowid.Events.Payloads.InvoiceTransactionsDisconnected
        ],
        sales_invoice_transactions_connected: [
          type: Firmowid.Events.Payloads.InvoiceTransactionsConnected
        ],
        sales_invoice_transactions_disconnected: [
          type: Firmowid.Events.Payloads.InvoiceTransactionsDisconnected
        ]
      ]
    ]
end
