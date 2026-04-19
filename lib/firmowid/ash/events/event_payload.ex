defmodule Firmowid.Ash.Events.EventPayload do
  @moduledoc """
  Union of all typed event-family payloads stored in `ash_events`.
  """

  use Ash.Type.NewType,
    subtype_of: :union,
    constraints: [
      types: [
        bank_account_sync_succeeded: [
          type: Firmowid.Ash.Events.Payloads.BankAccountSyncSucceeded
        ],
        bank_account_sync_failed: [
          type: Firmowid.Ash.Events.Payloads.BankAccountSyncFailed
        ],
        cost_invoice_transactions_connected: [
          type: Firmowid.Ash.Events.Payloads.InvoiceTransactionsConnected
        ],
        cost_invoice_transactions_disconnected: [
          type: Firmowid.Ash.Events.Payloads.InvoiceTransactionsDisconnected
        ],
        sales_invoice_transactions_connected: [
          type: Firmowid.Ash.Events.Payloads.InvoiceTransactionsConnected
        ],
        sales_invoice_transactions_disconnected: [
          type: Firmowid.Ash.Events.Payloads.InvoiceTransactionsDisconnected
        ]
      ]
    ]
end
