defmodule Firmowid.Finances.Transaction.Types.SalarySuggestion do
  @moduledoc "An unassigned monthly salary that one outgoing transfer may pay."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        user_id: [type: :uuid, allow_nil?: false, description: "The employee's user ID."],
        name: [type: :string, allow_nil?: false, description: "The employee's name or email."],
        month: [type: :date, allow_nil?: false, description: "First day of the salary month."],
        expected_amount: [
          type: AshMoney.Types.Money,
          allow_nil?: false,
          description: "Closest estimated payout, or gross pay when the contract type is unknown."
        ],
        payout_variant: [
          type: :atom,
          constraints: [
            one_of: [
              :uop,
              :uz_social,
              :uz_social_with_sickness,
              :uz_health,
              :uz_student,
              :uod_20,
              :uod_50,
              :b2b
            ]
          ],
          description: "Estimated payout variant, selected from a complete current profile or hypothetical assumptions."
        ],
        difference: [
          type: AshMoney.Types.Money,
          allow_nil?: false,
          description: "Absolute difference between the transfer and the expected amount."
        ],
        named_month?: [
          type: :boolean,
          allow_nil?: false,
          description: "Whether the transfer title names this salary's month, e.g. Wynagrodzenie 09/26."
        ],
        confidence: [
          type: :atom,
          allow_nil?: false,
          constraints: [one_of: [:high, :mid]],
          description:
            "high when the title names the month, the recipient is the employee by account or full name " <>
              "and the amount is within the tolerance, or when the amount is exact and the recipient " <>
              "resembles the employee; mid otherwise."
        ]
      ]
    ]
end
