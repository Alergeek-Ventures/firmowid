defmodule Firmowid.Analysis.YearSummary do
  @moduledoc "Authorized annual analysis using the monthly totals and separate original-currency summaries."
  use Ash.Resource,
    domain: Firmowid.Analysis,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.AtLeastRole

  code_interface do
    define :get, args: [:year]
  end

  actions do
    action :get, :map do
      description "Return all twelve months and annual totals using the monthly analysis rules."
      allow_nil? false

      argument :year, :integer, allow_nil?: false, constraints: [min: 1, max: 9999]

      argument :tag_filters, {:array, :term},
        allow_nil?: false,
        default: [],
        description:
          "Monthly tag-share filters: {:company}, {:taxes}, or {:project, tag_definition_id}, with OR semantics."

      constraints fields: [
                    year: [type: :integer, allow_nil?: false],
                    currency: [type: :string, allow_nil?: false],
                    months: [type: {:array, :map}, allow_nil?: false],
                    totals: [type: :map, allow_nil?: false],
                    totals_by_currency: [type: :map, allow_nil?: false]
                  ]

      run Firmowid.Analysis.Actions.GetYearSummary
    end
  end

  policies do
    policy action(:get) do
      authorize_if {AtLeastRole, role: :invoicing}
    end
  end
end
