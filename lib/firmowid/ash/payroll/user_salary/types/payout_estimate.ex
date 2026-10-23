defmodule Firmowid.Ash.Payroll.UserSalary.Types.PayoutEstimate do
  @moduledoc "An indicative payout under an explicitly assumed contract and deduction variant."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        variant: [
          type: :atom,
          allow_nil?: false,
          constraints: [
            one_of: [:uop, :uz_social, :uz_health, :uz_student, :uod_20, :uod_50, :b2b]
          ]
        ],
        amount: [type: AshMoney.Types.Money, allow_nil?: false],
        social: [type: AshMoney.Types.Money, allow_nil?: false],
        health: [type: AshMoney.Types.Money, allow_nil?: false],
        tax: [type: AshMoney.Types.Money, allow_nil?: false],
        youth_relief?: [type: :boolean, allow_nil?: false]
      ]
    ]
end
