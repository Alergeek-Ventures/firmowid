defmodule Firmowid.Analysis.Entry do
  @moduledoc "Entries behind the analysis dashboard: invoices and standalone transactions with their categories."
  use Ash.Resource,
    domain: Firmowid.Analysis,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.AtLeastRole

  code_interface do
    define :list, args: [:from, :to]
  end

  actions do
    action :list, :map do
      description "List the analysis entries of a period, as counted on the analysis dashboard, " <>
                    "with their expense or income category, counterparty register data and project allocation."

      allow_nil? false

      argument :from, :date,
        allow_nil?: false,
        description: "Any day of the period's first month."

      argument :to, :date,
        allow_nil?: false,
        description: "Any day of the period's last month; the period covers whole months, at most 12."

      constraints fields: [
                    industry: [type: :atom, allow_nil?: false],
                    entries: [
                      type: {:array, :map},
                      allow_nil?: false,
                      constraints: [
                        items: [
                          fields: [
                            id: [type: :uuid, allow_nil?: false],
                            entity_type: [
                              type: :atom,
                              allow_nil?: false,
                              constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]
                            ],
                            section: [
                              type: :atom,
                              allow_nil?: false,
                              constraints: [one_of: [:income, :expenses]]
                            ],
                            counterparty: [type: :string],
                            counterparty_nip: [type: :string],
                            registered_activity: [type: :string],
                            description: [type: :string],
                            date: [type: :date],
                            month: [type: :date, allow_nil?: false],
                            amount: [type: :decimal],
                            currency: [type: :string],
                            amount_pln: [type: :decimal],
                            category: [type: :atom],
                            category_source: [
                              type: :atom,
                              constraints: [one_of: [:owner, :rule, :classifier]]
                            ],
                            category_probability: [type: :float],
                            internal: [type: :boolean, allow_nil?: false],
                            allocation: [
                              type: {:array, :map},
                              allow_nil?: false,
                              constraints: [
                                items: [
                                  fields: [
                                    kind: [
                                      type: :atom,
                                      allow_nil?: false,
                                      constraints: [
                                        one_of: [
                                          :project,
                                          :shared_cost,
                                          :company,
                                          :taxes,
                                          :unassigned
                                        ]
                                      ]
                                    ],
                                    name: [type: :string],
                                    amount_pln: [type: :decimal, allow_nil?: false]
                                  ]
                                ]
                              ]
                            ]
                          ]
                        ]
                      ]
                    ]
                  ]

      run Firmowid.Analysis.Actions.ListEntries
    end
  end

  policies do
    policy action(:list) do
      authorize_if {AtLeastRole, role: :invoicing}
    end
  end
end
