defmodule Firmowid.Ash.Finances.Transaction.Types.SalarySuggestion do
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
          description: "Salary due for that month."
        ],
        difference: [
          type: AshMoney.Types.Money,
          allow_nil?: false,
          description: "Absolute difference between the transfer and the expected amount."
        ]
      ]
    ]
end
