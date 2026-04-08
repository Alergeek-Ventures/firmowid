defmodule Firmowid.Ash.Invoicing.Counterparty do
  @moduledoc """
  Ash resource for counterparties (buyers) linked to sales invoices.

  Stores buyer information reusable across invoices. Supports full CRUD,
  ParadeDB full-text search, and type-specific validations (NIP, EU VAT, etc.).

  ## Calculations

    * `:display_label` — human-friendly name (display_name > full_name > given_name surname)
    * `:tax_id_type` — `:nip | :eu_vat | :other_id | :optional_id | :no_id`


  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Invoicing.Changes.ClearIrrelevantBuyerFields
  alias Firmowid.Ash.Invoicing.Changes.ValidateCountryCode
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.Validations.ValidateNameFields
  alias Firmowid.Ash.Invoicing.Validations.ValidateTaxId
  alias Firmowid.Ash.Resource

  require Ash.Query
  require Resource

  @eu_countries CountryCodes.eu_countries_with_aliases()

  postgres do
    table "counterparties"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :list_all, action: :list_all
    define :get, args: [:id], action: :by_id
    define :create
    define :update
    define :destroy

    define :search,
      args: [
        :search_term,
        {:optional, :type},
        {:optional, :sort_by},
        {:optional, :sort_order}
      ]
  end

  actions do
    defaults [:read, :destroy]

    read :by_id do
      get_by [:id]
    end

    read :list_all do
      prepare build(sort: [list_all_order: :asc])
    end

    create :create do
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

      validate {ValidateTaxId, id_field: :tax_id, country_field: :country, pesel_field: :pesel, type_field: :type}

      validate {ValidateNameFields,
                type_field: :type, full_name_field: :full_name, given_name_field: :given_name, surname_field: :surname}
    end

    update :update do
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

      validate {ValidateTaxId, id_field: :tax_id, country_field: :country, pesel_field: :pesel, type_field: :type}

      validate {ValidateNameFields,
                type_field: :type, full_name_field: :full_name, given_name_field: :given_name, surname_field: :surname}
    end

    read :search do
      description "Full-text search counterparties via ParadeDB."

      argument :search_term, :string
      argument :type, :atom, constraints: [one_of: [:individual, :company]]
      argument :sort_by, :atom, default: :name

      argument :sort_order, :atom,
        default: :asc,
        constraints: [one_of: [:asc, :desc]]

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
               columns: ~w(display_name full_name given_name surname tax_id email),
               operator: :disjunction,
               argument: :search_term}

      prepare Firmowid.Ash.Invoicing.Preparations.CounterpartySearchSort

      filter expr(is_nil(^arg(:type)) or type == ^arg(:type))

      prepare build(limit: 25)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # Invoicing system roles: read-only
    bypass {Firmowid.Ash.Checks.SystemActorRole,
            roles: [:sales_invoice_processor, :cost_invoice_processor, :invoice_matcher]} do
      authorize_if action_type(:read)
    end

    # Other system actors: no access
    policy Firmowid.Ash.Checks.IsSystemActor do
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
    attribute :full_name, :string, public?: true
    attribute :given_name, :string, public?: true
    attribute :surname, :string, public?: true
    attribute :pesel, :string, public?: true
    attribute :display_name, :string, public?: true
    attribute :address, :string, public?: true
    attribute :country, :string, public?: true
    attribute :is_different_mail_address, :boolean, public?: true, default: false
    attribute :mail_address, :string, public?: true
    attribute :mail_country, :string, public?: true
    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :description, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  calculations do
    # TODO: Rename to :display_name_label for consistency with
    # SalesInvoice.buyer_display_name_label and WizardDraft.buyer_display_name_label.
    calculate :display_label,
              :string,
              expr(
                cond do
                  not is_nil(display_name) and display_name != "" -> display_name
                  type == :company -> full_name
                  true -> given_name <> " " <> surname
                end
              )

    # NOTE: This expr() logic is intentionally duplicated across Counterparty,
    # SalesInvoice (as :buyer_id_type), and WizardDraft (as :buyer_id_type)
    # because Ash expr() runs in the DB. Runtime equivalent: CountryCodes.tax_id_type/3
    calculate :tax_id_type,
              :atom,
              expr(
                cond do
                  not is_nil(pesel) and pesel != "" ->
                    :no_id

                  type == :individual and country == "PL" ->
                    :no_id

                  country == "PL" ->
                    :nip

                  country in ^@eu_countries ->
                    :eu_vat

                  country == "US" ->
                    :optional_id

                  true ->
                    :other_id
                end
              )

    calculate :list_all_order, :string, expr(fragment("COALESCE(?, ?)", display_name, surname))
  end
end
