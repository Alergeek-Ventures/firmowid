defmodule Firmowid.Ash.Invoicing.WizardDraft do
  @moduledoc """
  Ash resource backed by ETS for the sales invoice creator wizard.

  Replaces `CreatorDraftStore` (Cachex). Typed fields, proper validations
  per wizard step, ephemeral (dies on restart — no persistence needed).

  ## Actions

    * `:create` — start a new wizard draft
    * `:update_counterparty` — step 1: counterparty data, advances to :items
    * `:update_items` — step 2: line items, advances to :payment
    * `:update_payment` — step 3: payment data, advances to :preview
    * `:populate_from_invoice` — populate from an existing invoice (copy flow)
    * `:read` — default read
    * `:destroy` — delete a draft (cascades items)

  ## ETS scoping

  `private? false` means the ETS table is managed by `Ash.DataLayer.Ets.TableManager`,
  a GenServer that owns a named, public table shared across all processes. Drafts
  persist for the BEAM VM lifecycle. Multitenancy via `organization_id` provides
  org isolation, same as Postgres resources.

  ## Items relationship

  Items are stored as standalone ETS resources in `WizardDraft.Item`. This enables
  Ash aggregates (sum net_value, vat_value, gross_value) and expression calculations
  on items, eliminating the need for the `draft_to_invoice` struct-building workaround.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Invoicing.Changes
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.Validations
  alias Firmowid.Ash.Invoicing.WizardDraft

  @eu_countries CountryCodes.eu_countries_with_aliases()

  ets do
    private? false
  end

  code_interface do
    define :create, action: :create
    define :update_counterparty, action: :update_counterparty
    define :update_items, action: :update_items
    define :update_payment, action: :update_payment
    define :update_notes, action: :update_notes
    define :populate_from_invoice, action: :populate_from_invoice
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read]

    destroy :destroy do
      primary? true
      require_atomic? false
      change cascade_destroy(:items)
    end

    create :create do
      primary? true
      accept [:organization_id]
    end

    update :update_counterparty do
      require_atomic? false

      accept [
        :counterparty_id,
        :buyer_type,
        :buyer_id,
        :buyer_full_name,
        :buyer_given_name,
        :buyer_surname,
        :buyer_pesel,
        :buyer_display_name,
        :buyer_address,
        :buyer_country,
        :buyer_email,
        :buyer_phone,
        :buyer_description,
        :invoice_type,
        :is_reverse_charge,
        :currency,
        :seller_account_number
      ]

      change {Changes.ValidateCountryCode, field: :buyer_country}

      change {Changes.ClearIrrelevantBuyerFields,
              type_field: :buyer_type,
              company_fields: [:buyer_id, :buyer_full_name],
              individual_fields: [:buyer_pesel, :buyer_given_name, :buyer_surname]}

      change {Changes.CastBasedOnInvoiceType, []}
      change set_attribute(:step, :items)

      validate {Validations.ValidateTaxId,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate {Validations.ValidateNameFields,
                type_field: :buyer_type,
                full_name_field: :buyer_full_name,
                given_name_field: :buyer_given_name,
                surname_field: :buyer_surname}

      validate {Validations.ValidateBuyerIdRequired,
                id_field: :buyer_id, country_field: :buyer_country, pesel_field: :buyer_pesel, type_field: :buyer_type}

      validate present([:buyer_country, :buyer_address])
    end

    update :update_items do
      require_atomic? false

      accept [:currency, :is_reverse_charge]

      argument :items, {:array, :map}

      change manage_relationship(:items, type: :direct_control)
      change {Changes.NormalizeReverseChargeVatRates, source: :argument, field: :items}
      change set_attribute(:step, :payment)

      validate present([:currency]), message: "Waluta jest wymagana"
      validate match(:currency, ~r/^[A-Z]{3}$/), message: "Nieprawidłowy kod waluty"
      validate {Validations.ValidateItemsNotEmpty, field: :items, source: :argument}
    end

    update :update_payment do
      require_atomic? false

      accept [:sale_date, :due_date, :payment_method, :seller_account_number]
      change set_attribute(:step, :preview)

      validate present([:sale_date]), message: "Data sprzedaży jest wymagana"
      validate present([:due_date]), message: "Termin płatności jest wymagany"
      validate present([:payment_method]), message: "Forma płatności jest wymagana"

      validate {Validations.ValidateSellerAccountForTransfer,
                payment_method_field: :payment_method, seller_account_field: :seller_account_number}
    end

    # Preview step: update invoice and internal notes
    update :update_notes do
      require_atomic? false

      accept [:invoice_note, :internal_note]
    end

    # Resets the bank account number without running payment step validations.
    # Used when currency changes in step 2 — payment fields aren't set yet.
    update :reset_bank_account do
      require_atomic? false
      change set_attribute(:seller_account_number, nil)
    end

    # For copy-from-invoice: populate multiple steps at once
    update :populate_from_invoice do
      require_atomic? false

      accept [
        :counterparty_id,
        :buyer_type,
        :buyer_id,
        :buyer_full_name,
        :buyer_given_name,
        :buyer_surname,
        :buyer_pesel,
        :buyer_display_name,
        :buyer_address,
        :buyer_country,
        :buyer_email,
        :buyer_phone,
        :buyer_description,
        :invoice_type,
        :is_reverse_charge,
        :currency,
        :seller_account_number,
        :sale_date,
        :due_date,
        :payment_method,
        :invoice_note,
        :internal_note
      ]

      argument :items, {:array, :map}

      change manage_relationship(:items, type: :direct_control)

      # Minimal validation -- the source invoice was already valid
      change {Changes.ValidateCountryCode, field: :buyer_country}
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # Other system actors: no access
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # :accountant and above: all actions
    policy {Firmowid.Ash.Checks.AtLeastRole, role: :accountant} do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :organization_id, :uuid_v7, allow_nil?: false, public?: true

    attribute :step, :atom,
      constraints: [one_of: [:counterparty, :items, :payment, :preview]],
      default: :counterparty,
      public?: true

    # Step 1 -- Counterparty
    attribute :counterparty_id, :uuid_v7, public?: true

    attribute :buyer_type, :atom,
      constraints: [one_of: [:individual, :company]],
      default: :company,
      public?: true

    attribute :buyer_id, :string, public?: true
    attribute :buyer_full_name, :string, public?: true
    attribute :buyer_given_name, :string, public?: true
    attribute :buyer_surname, :string, public?: true
    attribute :buyer_pesel, :string, public?: true
    attribute :buyer_display_name, :string, public?: true
    attribute :buyer_address, :string, public?: true
    attribute :buyer_country, :string, public?: true
    attribute :buyer_email, :string, public?: true
    attribute :buyer_phone, :string, public?: true
    attribute :buyer_description, :string, public?: true
    attribute :invoice_note, :string, public?: true
    attribute :internal_note, :string, public?: true

    attribute :invoice_type, :atom,
      constraints: [one_of: [:poland, :foreign]],
      default: :poland,
      public?: true

    attribute :is_reverse_charge, :boolean, default: false, public?: true
    attribute :currency, :string, default: "PLN", public?: true
    attribute :seller_account_number, :string, public?: true

    # Step 3 -- Payment
    attribute :sale_date, :date, public?: true
    attribute :due_date, :date, public?: true

    attribute :payment_method, :atom,
      constraints: [one_of: [:cash, :card, :voucher, :check, :credit, :transfer, :mobile]],
      public?: true

    create_timestamp :inserted_at, type: :utc_datetime, public?: true
    update_timestamp :updated_at, type: :utc_datetime, public?: true
  end

  relationships do
    has_many :items, WizardDraft.Item do
      destination_attribute :wizard_draft_id
    end
  end

  calculations do
    # NOTE: This expr() logic is intentionally duplicated across SalesInvoice,
    # WizardDraft, and Counterparty (as :tax_id_type) because Ash expr()
    # calculations run in the DB and cannot call Elixir functions.
    # Runtime equivalent: CountryCodes.tax_id_type/3
    calculate :buyer_id_type,
              :atom,
              expr(
                cond do
                  not is_nil(buyer_pesel) and buyer_pesel != "" ->
                    :no_id

                  buyer_type == :individual and buyer_country == "PL" ->
                    :no_id

                  buyer_country == "PL" ->
                    :nip

                  buyer_country in ^@eu_countries ->
                    :eu_vat

                  buyer_country == "US" ->
                    :optional_id

                  true ->
                    :other_id
                end
              ) do
      description "Tax ID type for the buyer based on country, PESEL, and buyer type."
    end

    # Display name calculation — mirrors SalesInvoice.buyer_display_name_label
    calculate :buyer_display_name_label,
              :string,
              expr(
                cond do
                  not is_nil(buyer_display_name) and buyer_display_name != "" ->
                    buyer_display_name

                  buyer_type == :company ->
                    buyer_full_name

                  true ->
                    buyer_given_name <> " " <> buyer_surname
                end
              )
  end

  aggregates do
    sum :net_value, :items, :net_value
    sum :vat_value, :items, :vat_value
    sum :gross_value, :items, :gross_value
  end
end
