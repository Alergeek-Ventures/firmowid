# credo:disable-for-this-file ExDNA.Credo
# Create/update action and expr duplication is intentional for Ash runtime/SQL parity;
# removing it cleanly requires shared action/calc extraction used by multiple resources.
defmodule Firmowid.Invoicing.Counterparty do
  @moduledoc """
  Ash resource for counterparties (buyers) linked to sales invoices.

  Stores buyer information reusable across invoices. Supports full CRUD,
  ParadeDB full-text search, and type-specific validations (NIP, EU VAT, etc.).

  ## Calculations

    * `:display_label` — human-friendly name (display_name > full_name > given_name surname)
    * `:tax_id_type` — `:nip | :eu_vat | :other_id | :optional_id | :no_id`


  """
  use Ash.Resource,
    domain: Firmowid.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Invoicing.Calculations.TaxIdType
  alias Firmowid.Invoicing.Changes.ClearIrrelevantBuyerFields
  alias Firmowid.Invoicing.Changes.EnqueueVatIdCheck
  alias Firmowid.Invoicing.Changes.NormalizeBlankCounterpartyFields
  alias Firmowid.Invoicing.Changes.NormalizeCounterpartyTaxId
  alias Firmowid.Invoicing.Changes.ValidateCountryCode
  alias Firmowid.Invoicing.Validations.ValidateEuVatNumber
  alias Firmowid.Invoicing.Validations.ValidateNameFields
  alias Firmowid.Invoicing.Validations.ValidateTaxId
  alias Firmowid.Resource

  require Resource

  postgres do
    table "counterparties"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :list, action: :list
    define :get, args: [:id], action: :by_id
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    read :by_id do
      description "Fetch a counterparty by ID."
      get_by [:id]
    end

    read :list do
      description "List counterparties with search, status, and type filters."
      argument :search, :string
      argument :type, :atom, constraints: [one_of: [:individual, :company]]

      argument :status, :atom,
        default: :active,
        constraints: [one_of: [:active, :archived, :all]]

      argument :sort_by, :atom,
        default: :name,
        constraints: [one_of: [:name, :display_name, :created_at]]

      argument :sort_order, :atom,
        default: :asc,
        constraints: [one_of: [:asc, :desc]]

      argument :limit, :integer do
        constraints min: 1, max: 100
      end

      argument :vat_id_statuses, {:array, :atom},
        constraints: [items: [one_of: [:active, :inactive, :invalid]]],
        description: "Only counterparties whose last EU VAT number check gave one of these results."

      argument :vat_id_due_before, :utc_datetime_usec,
        description: "Only counterparties with an EU VAT number never checked or last checked before this time."

      prepare {Firmowid.Preparations.ParadeDBSearch,
               columns: ~w(display_name full_name given_name surname tax_id email)a,
               operator: :disjunction,
               argument: :search}

      prepare Firmowid.Invoicing.Preparations.CounterpartySearchSort

      prepare build(filter: expr(type == ^arg(:type))) do
        where present(:type)
      end

      prepare build(filter: expr(is_nil(archived_at))) do
        where argument_equals(:status, :active)
      end

      prepare build(filter: expr(not is_nil(archived_at))) do
        where argument_equals(:status, :archived)
      end

      prepare build(limit: arg(:limit)) do
        where present(:limit)
      end

      prepare build(filter: expr(vat_id_status in ^arg(:vat_id_statuses))) do
        where present(:vat_id_statuses)
      end

      prepare build(
                filter:
                  expr(
                    tax_id_type == :eu_vat and not is_nil(tax_id) and
                      (is_nil(vat_id_checked_at) or vat_id_checked_at < ^arg(:vat_id_due_before))
                  )
              ) do
        where present(:vat_id_due_before)
      end
    end

    create :create do
      description "Create a reusable counterparty for invoicing."

      accept [
        :type,
        :tax_id,
        :full_name,
        :given_name,
        :surname,
        :pesel,
        :display_name,
        :address,
        :country,
        :is_different_mail_address,
        :mail_address,
        :mail_country,
        :email,
        :phone,
        :description
      ]

      change NormalizeBlankCounterpartyFields
      change {ValidateCountryCode, field: :country}
      change {ValidateCountryCode, field: :mail_country}

      change {ClearIrrelevantBuyerFields,
              type_field: :type,
              company_fields: [:tax_id, :full_name],
              individual_fields: [
                :pesel,
                :given_name,
                :surname
              ]}

      change NormalizeCounterpartyTaxId
      change EnqueueVatIdCheck

      validate {ValidateTaxId, id_field: :tax_id, country_field: :country, pesel_field: :pesel, type_field: :type}

      validate {ValidateEuVatNumber, id_field: :tax_id, country_field: :country, pesel_field: :pesel, type_field: :type}

      validate {ValidateNameFields,
                type_field: :type, full_name_field: :full_name, given_name_field: :given_name, surname_field: :surname}
    end

    update :update do
      description "Update counterparty details and validations."
      primary? true
      # ValidateEuVatNumber checks the submitted number in Elixir.
      require_atomic? false

      accept [
        :type,
        :tax_id,
        :full_name,
        :given_name,
        :surname,
        :pesel,
        :display_name,
        :address,
        :country,
        :is_different_mail_address,
        :mail_address,
        :mail_country,
        :email,
        :phone,
        :description
      ]

      change NormalizeBlankCounterpartyFields
      change {ValidateCountryCode, field: :country}
      change {ValidateCountryCode, field: :mail_country}

      change {ClearIrrelevantBuyerFields,
              type_field: :type,
              company_fields: [:tax_id, :full_name],
              individual_fields: [
                :pesel,
                :given_name,
                :surname
              ]}

      change NormalizeCounterpartyTaxId

      # A changed number or country has not been checked yet.
      change set_attribute(:vat_id_status, nil) do
        where any([changing(:tax_id), changing(:country)])
      end

      change set_attribute(:vat_id_checked_at, nil) do
        where any([changing(:tax_id), changing(:country)])
      end

      change EnqueueVatIdCheck do
        where any([changing(:tax_id), changing(:country)])
      end

      validate {ValidateTaxId, id_field: :tax_id, country_field: :country, pesel_field: :pesel, type_field: :type}

      validate {ValidateEuVatNumber, id_field: :tax_id, country_field: :country, pesel_field: :pesel, type_field: :type}

      validate {ValidateNameFields,
                type_field: :type, full_name_field: :full_name, given_name_field: :given_name, surname_field: :surname}
    end

    update :record_vat_id_check do
      description "Record the result of the periodic EU VAT number check."
      accept [:vat_id_status, :vat_id_checked_at]
    end

    update :archive do
      description "Archive a counterparty by setting archived_at to today."
      accept []
      require_atomic? false

      change set_attribute(:archived_at, &Date.utc_today/0)
    end

    update :unarchive do
      description "Unarchive a counterparty by clearing archived_at."
      accept []
      require_atomic? false

      change set_attribute(:archived_at, nil)
    end
  end

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    # Invoicing system roles: read-only
    bypass {SystemActorRole, roles: [:sales_invoice_processor, :cost_invoice_processor, :invoice_matcher]} do
      authorize_if action_type(:read)
    end

    bypass {SystemActorRole, roles: [:vat_id_checker]} do
      authorize_if action([:list, :record_vat_id_check])
    end

    # Other system actors: no access
    policy Firmowid.Checks.IsSystemActor do
      forbid_if always()
    end

    # :invoicing and :accountant: read
    policy [action_type(:read), {AtLeastRole, role: :invoicing}] do
      authorize_if always()
    end

    # :accountant: write
    policy [
      action_type([:create, :update, :destroy]),
      {AtLeastRole, role: :accountant}
    ] do
      authorize_if always()
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "counterparty"

    publish :record_vat_id_check, ["vat_id_checked", :id]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :type, :atom,
      public?: true,
      constraints: [one_of: [:individual, :company]],
      default: :company

    attribute :tax_id, :string, public?: true
    attribute :normalized_tax_id, :string, public?: false
    attribute :full_name, :string, public?: true
    attribute :given_name, :string, public?: true
    attribute :surname, :string, public?: true
    attribute :pesel, :string, public?: true
    attribute :display_name, :string, public?: true
    attribute :address, :string, public?: true
    attribute :country, :string, public?: true, allow_nil?: false
    attribute :archived_at, :date, public?: true
    attribute :is_different_mail_address, :boolean, public?: true, default: false
    attribute :mail_address, :string, public?: true
    attribute :mail_country, :string, public?: true
    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :description, :string, public?: true

    attribute :vat_id_status, :atom,
      public?: true,
      constraints: [one_of: [:active, :inactive, :invalid]],
      description: "Last EU VAT number check: active or inactive in VIES, or invalid for its country's rules."

    attribute :vat_id_checked_at, :utc_datetime_usec, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    has_many :sales_invoices, Firmowid.Invoicing.SalesInvoice
  end

  calculations do
    # TODO: Rename to :display_name_label for consistency with
    # SalesInvoice.buyer_display_name_label and WizardState.buyer_display_name_label.
    calculate :display_label,
              :string,
              expr(
                cond do
                  not is_nil(display_name) and display_name != "" -> display_name
                  type == :company -> full_name
                  true -> given_name <> " " <> surname
                end
              )

    calculate :tax_id_type,
              :atom,
              {TaxIdType, pesel: :pesel, type: :type, country: :country}

    calculate :cooperation_value, :map, calculation: Firmowid.Invoicing.Calculations.CooperationValue
  end

  identities do
    identity :unique_tax_id_country_per_org, [:normalized_tax_id, :country, :organization_id],
      nils_distinct?: true,
      message: gettext_noop("a counterparty with this tax ID already exists")

    identity :unique_pesel_per_org, [:pesel, :organization_id],
      nils_distinct?: true,
      message: gettext_noop("a counterparty with this PESEL number already exists")
  end
end
