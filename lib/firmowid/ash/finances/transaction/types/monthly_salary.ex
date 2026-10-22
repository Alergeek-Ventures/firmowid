defmodule Firmowid.Ash.Finances.Transaction.Types.MonthlySalary do
  @moduledoc "One employee's salary for a month and the transfer that pays it."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        user_id: [type: :uuid, allow_nil?: false, description: "The employee's user ID."],
        name: [type: :string, allow_nil?: false, description: "The employee's name or email."],
        month: [type: :date, allow_nil?: false, description: "First day of the salary month."],
        hourly_rate: [
          type: :decimal,
          allow_nil?: false,
          description: "Hourly rate in PLN active at the month's end."
        ],
        expected_amount: [
          type: AshMoney.Types.Money,
          allow_nil?: false,
          description:
            "Hourly rate multiplied by the hours logged in the month, rounded up to full hours. Calculated, not a " <>
              "recorded payout amount."
        ],
        hours_submission_status: [
          type: :atom,
          allow_nil?: false,
          constraints: [one_of: [:submitted, :withdrawn, :missing]],
          description: "State of the employee's hours record for the month."
        ],
        connected_transaction_id: [
          type: :uuid,
          description: "Transfer assigned to this salary, null when unpaid."
        ]
      ]
    ]
end
