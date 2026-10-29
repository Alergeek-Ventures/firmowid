defmodule Firmowid.Core.Organization.Types.TaxForecastSettings do
  @moduledoc """
  Explicit organization-wide invoice planning assumptions, not a PIT/CIT regime.

  No rate or consent is assumed. `invoice_costs_deductible: true` accepts using
  every recorded cost invoice's payment amount less explicitly qualified input
  VAT as a planning expense, including non-deductible VAT and settlement charges.
  This convention deliberately does not establish statutory deductible costs.
  """
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      preserve_nil_values?: true,
      fields: [
        income_reserve_rate: [type: :decimal, constraints: [min: 0, max: 100]],
        invoice_costs_deductible: [type: :boolean]
      ]
    ]
end
