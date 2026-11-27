defmodule Firmowid.Taxes.TaxYear do
  @moduledoc """
  How the company is taxed in one calendar year.

  The income tax form is chosen per year, so each year has its own record and
  past years keep the settings they were settled with. The organization's
  `legal_form` decides which fields apply: a limited company pays CIT itself,
  while the owners of a sole proprietorship or a civil partnership are its
  `partners` and pay their own income tax and ZUS on its profit.
  """
  use Ash.Resource,
    domain: Firmowid.Taxes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias AshOban.Checks.AshObanInteraction
  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.LocalDate
  alias Firmowid.Resource
  alias Firmowid.Taxes.TaxYear.Actions.Forecast
  alias Firmowid.Taxes.TaxYear.Actions.SaveForecasts
  alias Firmowid.Taxes.TaxYear.Actions.SuggestSettings
  alias Firmowid.Taxes.TaxYear.Changes.EnqueueForecasts
  alias Firmowid.Taxes.TaxYear.Changes.FitLegalForm

  require Resource

  @settings [:vat_period, :cit_rate, :cit_advances, :accident_insurance_rate]

  postgres do
    table "tax_years"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
    end
  end

  oban do
    scheduled_actions do
      schedule :save_forecasts, "10 5 * * *" do
        action :save_forecasts
        queue :default
        list_tenants {Firmowid.Invoicing.SalesInvoice.OrganizationTenantList, []}

        worker_module_name Firmowid.Taxes.TaxYear.Worker.SaveForecasts
      end
    end
  end

  actions do
    defaults [:read]

    read :list do
      description "List the organization's tax years, the latest first, optionally only one year."
      argument :year, :integer

      prepare build(sort: [year: :desc])

      prepare build(filter: expr(year == ^arg(:year))) do
        where present(:year)
      end
    end

    create :create do
      description "Set how the company is taxed in a new year, together with its partners."
      accept [:year | @settings]

      argument :partners, {:array, :map},
        allow_nil?: false,
        default: [],
        description: "The owners paying their own income tax; see `Firmowid.Taxes.Partner` for the fields."

      change manage_relationship(:partners,
               type: :direct_control,
               use_identities: [:_primary_key, :unique_member]
             )

      change FitLegalForm
      change EnqueueForecasts
    end

    update :update do
      description "Replace how the company is taxed in the year, together with the full list of its partners."
      require_atomic? false
      accept @settings

      # Required without a default: an update that leaves partners out must not remove them all.
      argument :partners, {:array, :map},
        allow_nil?: false,
        description: "The complete list of partners; a partner left out is removed, one matched by member is updated."

      change manage_relationship(:partners,
               type: :direct_control,
               use_identities: [:_primary_key, :unique_member]
             )

      change FitLegalForm

      # Saving confirms the year's suggestions (`Firmowid.Taxes.pending_suggestions/3`) also when
      # only partners change, which would leave the year's own timestamp as it was.
      change set_attribute(:updated_at, &DateTime.utc_now/0)

      change EnqueueForecasts
    end

    action :suggest_settings, {:array, :map} do
      description "Suggest the year's VAT period, income tax form and advances from the transfers to the tax " <>
                    "micro-account, and for a sole proprietorship's saved owner the ZUS social insurance, voluntary " <>
                    "sickness and lump sum rate that the payments equal to the grosz or the złoty. Not binding: an " <>
                    "admin confirms them by saving the year. Saves nothing."

      constraints items: [
                    fields: [
                      setting: [
                        type: :atom,
                        allow_nil?: false,
                        constraints: [
                          one_of: [
                            :vat_period,
                            :cit_advances,
                            :income_tax,
                            :pit_advances,
                            :social_insurance,
                            :voluntary_sickness,
                            :lump_sum_rate
                          ]
                        ]
                      ],
                      # An atom, a boolean (voluntary_sickness) or a decimal (lump_sum_rate, in percent);
                      # a generic action's result is not cast, so `:term` only says that it varies.
                      value: [type: :term, allow_nil?: false],
                      year: [type: :integer, allow_nil?: false],
                      transfers: [type: :integer, allow_nil?: false],
                      latest_transfer_at: [type: :utc_datetime, allow_nil?: false]
                    ]
                  ]

      argument :year, :integer, allow_nil?: false, constraints: [min: 2020, max: 2100]

      run SuggestSettings
    end

    action :forecast, {:array, :map} do
      description "Forecast the tax payments of the year's periods from its settings and the company's invoices: " <>
                    "VAT for a VAT payer with a saved VAT period, and CIT advances for a limited company with a saved " <>
                    "CIT rate and advance form, and for each partner of a sole proprietorship or a civil partnership " <>
                    "their PIT advances and ZUS contributions (the forecast's member_id is the partner). A year " <>
                    "without saved settings uses those of the latest saved year before it, and one without any saved " <>
                    "year the VAT period that the transfers to the tax micro-account suggest (VAT only; CIT, PIT and " <>
                    "ZUS need an owner, a rate or ZUS settings). The payments of the last three periods of a kind " <>
                    "that the bank history covers (a company connected recently has fewer) correct a forecast that " <>
                    "the documents do not track, up or down (outside 1.5 times the typical payment), and a kind " <>
                    "without settings is forecast from them alone. Saves nothing."

      constraints items: [
                    fields: [
                      kind: [
                        type: :atom,
                        allow_nil?: false,
                        constraints: [one_of: [:vat, :cit, :pit, :zus]]
                      ],
                      period: [type: :string, allow_nil?: false],
                      period_start: [type: :date, allow_nil?: false],
                      period_end: [type: :date, allow_nil?: false],
                      amount: [type: :decimal, allow_nil?: false],
                      due_date: [type: :date, allow_nil?: false],
                      description: [type: :string, allow_nil?: false],
                      member_id: [type: :uuid_v7],
                      details: [type: :map, allow_nil?: false]
                    ]
                  ]

      argument :year, :integer, allow_nil?: false, constraints: [min: 2020, max: 2100]

      # Today in Poland; the running period of this day's year is projected. A test passes a fixed date.
      argument :today, :date, allow_nil?: false, public?: false, default: &LocalDate.today/0

      run Forecast
    end

    action :save_forecasts, :integer do
      description "Keep the organization's upcoming tax and ZUS payments as expected transactions: recalculate " <>
                    "the forecasts of this year and the last one, add the payments that are due and not saved yet, " <>
                    "update the unfulfilled ones and remove those that are no longer due. Returns the number " <>
                    "of changes. Run daily for every organization by the scheduler, and for one organization " <>
                    "when its tax year is saved and about a minute after the data the forecast reads changes " <>
                    "(a bank sync, invoices, classified transfers, the organization's legal form, VAT payer or " <>
                    "cash accounting)."

      # All changes or none, so a failure leaves the expectations as they were for the next run.
      transaction? true

      # Today in Poland; a test passes a fixed date.
      argument :today, :date, allow_nil?: false, public?: false, default: &LocalDate.today/0

      run SaveForecasts
    end
  end

  policies do
    bypass AshObanInteraction do
      authorize_if action(:save_forecasts)
    end

    bypass {SystemActorRole, roles: [:tax_forecaster]} do
      authorize_if action_type(:read)
      authorize_if action([:forecast, :suggest_settings, :save_forecasts])
    end

    # Only the job saves the forecasts (daily, after a tax year is saved and after the data it reads
    # changes); nobody runs it by hand.
    policy action(:save_forecasts) do
      forbid_if always()
    end

    policy action_type([:read, :action]) do
      authorize_if {AtLeastRole, role: :accountant}
    end

    policy action_type([:create, :update]) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :year, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 2020, max: 2100]

    attribute :vat_period, :atom,
      public?: true,
      description: "How often a VAT payer settles VAT, due on the 25th; nil for a company outside VAT.",
      constraints: [one_of: [:monthly, :quarterly]]

    attribute :cit_rate, :atom,
      public?: true,
      description: "The CIT rate of a limited company: 9% for a small taxpayer (reduced) or 19% (standard).",
      constraints: [one_of: [:reduced, :standard]]

    attribute :cit_advances, :atom,
      public?: true,
      description: "How a limited company pays CIT advances: monthly, quarterly or simplified (fixed monthly).",
      constraints: [one_of: [:monthly, :quarterly, :simplified]]

    # The rate is the activity group's rate (0.67–3.33%) times the payer's correction
    # factor (0.5–1.5), or the flat 1.67% for payers reporting fewer than 10 insured.
    # ZUS may raise it to 150% for wrong IWA data or by 100% on a labour inspector's
    # request, so 10% is the highest rate a decision can set.
    attribute :accident_insurance_rate, :decimal,
      allow_nil?: false,
      public?: true,
      default: Decimal.new("1.67"),
      description: "The ZUS accident insurance rate in percent; 1.67 for employers reporting fewer than 10 insured.",
      constraints: [min: "0.34", max: "10.00"]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    has_many :partners, Firmowid.Taxes.Partner do
      public? true
    end
  end

  calculations do
    calculate :legal_form, :atom, expr(organization.legal_form) do
      public? true
      description "The organization's legal form, which decides the fields that apply."
    end
  end

  identities do
    identity :unique_year, [:year]
  end
end
