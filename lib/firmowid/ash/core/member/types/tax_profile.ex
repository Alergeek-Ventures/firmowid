defmodule Firmowid.Ash.Core.Member.Types.TaxProfile do
  @moduledoc """
  Current, explicitly supplied assumptions for payout forecasts, not historical declarations.

  Missing fields remain unknown. Annual PIT thresholds, the PLN 85,528 youth
  exemption and copyright-cost limits are not tracked by this profile.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        monthly_tax_reduction: [type: :integer],
        employment_costs: [
          type: :atom,
          constraints: [one_of: [:none, :standard, :increased]]
        ],
        mandate_insurance: [
          type: :atom,
          constraints: [one_of: [:student, :health, :social, :social_with_sickness]]
        ],
        civil_costs: [type: :atom, constraints: [one_of: [:standard_20, :copyright_50]]],
        youth_relief: [type: :atom, constraints: [one_of: [:automatic, :disabled]]]
      ]
    ]

  @impl true
  def apply_constraints(value, constraints) do
    with {:ok, profile} <- super(value, constraints) do
      if is_nil(profile) or Map.get(profile, :monthly_tax_reduction) in [nil, 0, 100, 150, 300] do
        {:ok, profile}
      else
        {:error, field: :monthly_tax_reduction, message: "must be one of %{values}", values: "0, 100, 150, 300"}
      end
    end
  end
end
