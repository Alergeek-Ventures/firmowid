defmodule Firmowid.Ash.Analysis.Entry do
  @moduledoc "Entries behind the analysis dashboard: invoices and standalone transactions with their categories."
  use Ash.Resource,
    domain: Firmowid.Ash.Analysis,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.AtLeastRole

  code_interface do
    define :list, args: [:month]
  end

  actions do
    action :list, :map do
      description "List a month's analysis entries with their categories, as shown on the analysis dashboard."
      allow_nil? false

      argument :month, :date,
        allow_nil?: false,
        description: "Any date within the analyzed month."

      constraints fields: [
                    month: [type: :date, allow_nil?: false],
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
                            description: [type: :string],
                            date: [type: :date],
                            amount: [type: :decimal],
                            currency: [type: :string],
                            categories: [
                              type: {:array, :map},
                              allow_nil?: false,
                              constraints: [
                                items: [
                                  fields: [
                                    kind: [
                                      type: :atom,
                                      allow_nil?: false,
                                      constraints: [
                                        one_of: [:project, :company, :taxes, :internal]
                                      ]
                                    ],
                                    name: [type: :string]
                                  ]
                                ]
                              ]
                            ]
                          ]
                        ]
                      ]
                    ]
                  ]

      run Firmowid.Ash.Analysis.Actions.ListEntries
    end
  end

  policies do
    policy action(:list) do
      authorize_if {AtLeastRole, role: :invoicing}
    end
  end
end
