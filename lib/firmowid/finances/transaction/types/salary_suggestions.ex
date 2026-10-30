defmodule Firmowid.Finances.Transaction.Types.SalarySuggestions do
  @moduledoc "Salary candidates for one transfer, with the reason when there are none."
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        suggestions: [
          type: {:array, Firmowid.Finances.Transaction.Types.SalarySuggestion},
          allow_nil?: false,
          description: "Candidate salaries, best match first."
        ],
        reason: [
          type: :atom,
          constraints: [
            one_of: [
              :not_outgoing_pln,
              :transaction_matched,
              :month_out_of_range,
              :no_logged_time,
              :no_salaries,
              :salaries_already_paid,
              :hours_not_submitted,
              :different_account,
              :amount_out_of_range
            ]
          ],
          description:
            "Why suggestions is empty: not_outgoing_pln, transaction_matched (already linked to an invoice or a " <>
              "salary), month_out_of_range (salary_month outside the six months before the transfer), " <>
              "no_logged_time (nobody logged time in that window), no_salaries (no salary rate in the considered " <>
              "months), salaries_already_paid, hours_not_submitted, different_account (the employees' stored bank " <>
              "accounts differ from the recipient's) or amount_out_of_range. Null when there are suggestions."
        ]
      ]
    ]
end
