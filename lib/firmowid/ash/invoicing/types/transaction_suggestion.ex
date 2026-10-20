defmodule Firmowid.Ash.Invoicing.Types.TransactionSuggestion do
  @moduledoc "A bank transaction scored as a payment of one invoice."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        transaction_id: [type: :uuid, allow_nil?: false],
        booking_date: [type: :date, allow_nil?: false],
        amount: [
          type: AshMoney.Types.Money,
          allow_nil?: false,
          description: "Signed amount; expenses are negative."
        ],
        counterparty_name: [
          type: :string,
          description: "Payer of a sales or payee of a cost invoice."
        ],
        title: [type: :string, description: "Transfer title from the bank."],
        connected: [
          type: :boolean,
          allow_nil?: false,
          description: "Already connected to this invoice."
        ],
        score: [
          type: :float,
          description:
            "Model match likelihood from 0 to 1, comparable only for ranking; " <>
              "absent for a connected transaction outside the invoice's matching window."
        ]
      ]
    ]
end
