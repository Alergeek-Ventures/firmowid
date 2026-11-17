defmodule Firmowid.Finances.Transaction.Types.DelegationSuggestion do
  @moduledoc "An approved business trip that one transfer may pay out or return money for."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        delegation_id: [type: :uuid, allow_nil?: false, description: "The delegation's ID."],
        reference: [
          type: :string,
          allow_nil?: false,
          description: "The delegation's public reference."
        ],
        title: [type: :string, allow_nil?: false, description: "The delegation's title."],
        user_id: [
          type: :uuid,
          allow_nil?: false,
          description: "The traveling employee's user ID."
        ],
        name: [type: :string, allow_nil?: false, description: "The employee's name or email."],
        start_date: [type: :date, allow_nil?: false, description: "First day of the trip."],
        end_date: [type: :date, allow_nil?: false, description: "Last day of the trip."],
        kind: [
          type: :atom,
          constraints: [one_of: [:advance, :settlement, :return]],
          description:
            "What the transfer most likely is: the advance paid out, the settlement paid out to the employee " <>
              "or the advance returned by the employee. Null when only the reference in the title points at the trip."
        ],
        expected_amount: [
          type: AshMoney.Types.Money,
          description: "The advance or settlement balance closest to the transfer; null together with kind."
        ],
        difference: [
          type: AshMoney.Types.Money,
          description: "Absolute difference between the transfer and the expected amount; null together with kind."
        ],
        reference_named?: [
          type: :boolean,
          allow_nil?: false,
          description: "Whether the transfer title contains the delegation's reference."
        ],
        confidence: [
          type: :atom,
          allow_nil?: false,
          constraints: [one_of: [:high, :mid]],
          description:
            "high when the title contains the reference, or the counterparty is the employee and the amount " <>
              "is exact; mid otherwise."
        ]
      ]
    ]
end
