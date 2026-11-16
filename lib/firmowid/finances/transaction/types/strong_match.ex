defmodule Firmowid.Finances.Transaction.Types.StrongMatch do
  @moduledoc "The confident suggestion for one pending transaction, waiting for confirmation."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        transaction_id: [
          type: :uuid,
          allow_nil?: false,
          description: "The pending transaction's ID."
        ],
        kind: [
          type: :atom,
          allow_nil?: false,
          constraints: [one_of: [:invoice, :salary, :delegation]],
          description: "What the transaction most likely pays: an invoice, a monthly salary or a business trip."
        ],
        name: [
          type: :string,
          description: "The invoice's counterparty, or the employee of the salary or business trip."
        ],
        reference: [
          type: :string,
          description: "The invoice number or the business trip's reference; null for a salary."
        ],
        month: [type: :date, description: "First day of the salary month; null otherwise."]
      ]
    ]
end
