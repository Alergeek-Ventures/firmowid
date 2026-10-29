defmodule Firmowid.Analysis.TaxForecast do
  @moduledoc """
  Monthly invoice-based tax reserves for planning, not a tax return or bank balance.

  `get(%{month: date}, scope: scope)` returns VAT and income-tax rows. Amounts are
  Decimal PLN values; unknown amounts remain nil. `:complete` only describes the
  recorded documents' input coverage, never the completeness of a tax register.
  The requested date is normalized to the first day of its month.
  """
  use Ash.Resource,
    domain: Firmowid.Analysis,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.AtLeastRole

  code_interface do
    define :get
  end

  actions do
    action :get, :map do
      description "Return monthly planning reserves with explicit assumptions and missing inputs, not taxes payable."
      allow_nil? false
      constraints preserve_nil_values?: true

      argument :month, :date, allow_nil?: false

      run Firmowid.Analysis.Actions.GetTaxForecast
    end
  end

  policies do
    policy action(:get) do
      authorize_if {AtLeastRole, role: :invoicing}
    end
  end
end
