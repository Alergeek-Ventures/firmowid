defmodule Firmowid.Ash.Finances.Transaction.Types.InvoiceSuggestion do
  @moduledoc "An unresolved invoice scored as paid by one bank transaction."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        invoice_type: [
          type: :atom,
          allow_nil?: false,
          constraints: [one_of: [:sales, :cost]],
          description: "sales for an incoming payment, cost for an outgoing one."
        ],
        invoice_id: [type: :uuid, allow_nil?: false],
        invoice_number: [type: :string],
        counterparty_name: [
          type: :string,
          description: "Buyer of a sales or seller of a cost invoice."
        ],
        issue_date: [type: :date],
        due_date: [type: :date],
        effective_amount: [
          type: AshMoney.Types.Money,
          description: "Gross amount after corrections; costs are negative."
        ],
        score: [
          type: :float,
          allow_nil?: false,
          description: "Model match likelihood from 0 to 1, comparable only for ranking."
        ]
      ]
    ]
end
