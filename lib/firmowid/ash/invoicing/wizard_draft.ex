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
    * `:destroy` — delete a draft

  ## ETS scoping

  `private? true` means the table is NOT publicly accessible outside the OTP
  app, but ALL processes within the app share it. Multitenancy via
  `organization_id` provides org isolation, same as Postgres resources.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Invoicing.Changes
  alias Firmowid.Ash.Invoicing.Validations
  alias Firmowid.Ash.Invoicing.WizardDraft

  ets do
    private? true
  end

  code_interface do
    define :create, action: :create
    define :update_counterparty, action: :update_counterparty
    define :update_items, action: :update_items
    define :update_payment, action: :update_payment
    define :populate_from_invoice, action: :populate_from_invoice
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

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

      accept [:currency, :is_reverse_charge, :items]

      change {Changes.NormalizeReverseChargeVatRates, source: :attribute, field: :items}
      change set_attribute(:step, :payment)

      validate present([:currency]), message: "Waluta jest wymagana"
      validate match(:currency, ~r/^[A-Z]{3}$/), message: "Nieprawidłowy kod waluty"
      validate {Validations.ValidateItemsNotEmpty, field: :items}
    end

    update :update_payment do
      require_atomic? false

      accept [:sale_date, :due_date, :payment_method, :seller_account_number]
      argument :due_date_days, :integer

      change {Changes.CalculateDueDate, []}
      change set_attribute(:step, :preview)

      validate present([:sale_date, :due_date, :payment_method, :seller_account_number]),
        message: "Pole jest wymagane"

      validate string_length(:seller_account_number, min: 10, max: 34),
        message: "Numer konta musi mieć od 10 do 34 znaków"
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
        :items,
        :sale_date,
        :due_date,
        :payment_method
      ]

      # Minimal validation -- the source invoice was already valid
      change {Changes.ValidateCountryCode, field: :buyer_country}
    end
  end

  policies do
    policy always() do
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

    attribute :invoice_type, :atom,
      constraints: [one_of: [:poland, :foreign]],
      default: :poland,
      public?: true

    attribute :is_reverse_charge, :boolean, default: false, public?: true
    attribute :currency, :string, default: "PLN", public?: true
    attribute :seller_account_number, :string, public?: true

    # Step 2 -- Items (embedded)
    attribute :items, {:array, WizardDraft.Item}, public?: true, default: []

    # Step 3 -- Payment
    attribute :sale_date, :date, public?: true
    attribute :due_date, :date, public?: true

    attribute :payment_method, :atom,
      constraints: [one_of: [:cash, :card, :voucher, :check, :credit, :transfer, :mobile]],
      public?: true

    create_timestamp :inserted_at, type: :utc_datetime, public?: true
    update_timestamp :updated_at, type: :utc_datetime, public?: true
  end
end
