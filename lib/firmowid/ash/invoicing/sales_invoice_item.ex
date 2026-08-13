# credo:disable-for-this-file ExDNA.Credo
# VAT mapping/calculation duplication is intentional to keep Ash expression behavior aligned
# between SQL and in-memory loading; removing it needs shared-calculation architecture changes.
defmodule Firmowid.Ash.Invoicing.SalesInvoiceItem do
  @moduledoc """
  Ash resource for sales invoice line items.

  ## Actions

    * `:read` — default read
    * `:create` — create a new item (used by `manage_relationship` on SalesInvoice)
    * `:update` — update an existing item
    * `:destroy` — delete an item

  ## Calculations

    * `:vat_rate_numeric` — converts KSeF string VAT rate to decimal (e.g. "23" → 0.23)
    * `:net_value` — quantity × unit_price
    * `:vat_value` — net_value × vat_rate_numeric
    * `:gross_value` — net_value + vat_value

  All are expression-based, SQL-pushable, and work on plain structs via `Ash.load!/3`.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Validations.ValidateVatRate
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "sales_invoice_items"
    repo Firmowid.Repo
  end

  code_interface do
    define :read, action: :read
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Create a sales invoice line item."
      primary? true
      accept [:index, :name, :quantity, :unit, :unit_price, :vat_rate]
      validate {ValidateVatRate, []}
    end

    update :update do
      description "Update a sales invoice line item."
      primary? true
      require_atomic? false
      accept [:index, :name, :quantity, :unit, :unit_price, :vat_rate]
      validate {ValidateVatRate, []}
    end
  end

  policies do
    policy accessing_from(SalesInvoice, :sales_invoice_items) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :index, :integer, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :quantity, :decimal, allow_nil?: false, public?: true
    attribute :unit, :string, allow_nil?: false, public?: true
    attribute :unit_price, :decimal, allow_nil?: false, public?: true
    attribute :vat_rate, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end

    belongs_to :sales_invoice, SalesInvoice do
      allow_nil? false
    end
  end

  calculations do
    # Converts KSeF string VAT rate code to numeric decimal.
    # All non-numeric rates (zw, oo, np I, np II, 0 KR, 0 WDT, 0 EX) → 0.
    # NOTE: kept as inline expr (not a shared module) because dependent calculations
    # (vat_value, gross_value) require it to be inlined for in-memory Ash.load!/3
    # on plain structs. A module-based expression/2 callback resolves correctly in SQL
    # but breaks the single-pass dependency chain for in-memory evaluation.
    # This mapping is duplicated in WizardDraft.Item — keep both in sync.
    calculate :vat_rate_numeric,
              :decimal,
              expr(
                cond do
                  vat_rate == "23" -> 0.23
                  vat_rate == "22" -> 0.22
                  vat_rate == "8" -> 0.08
                  vat_rate == "7" -> 0.07
                  vat_rate == "5" -> 0.05
                  vat_rate == "4" -> 0.04
                  vat_rate == "3" -> 0.03
                  true -> 0
                end
              )

    calculate :net_value, :decimal, expr(quantity * unit_price)
    calculate :vat_value, :decimal, expr(net_value * vat_rate_numeric)
    calculate :gross_value, :decimal, expr(net_value + vat_value)
  end
end
