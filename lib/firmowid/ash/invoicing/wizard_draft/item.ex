# credo:disable-for-this-file ExDNA.Credo
# This item resource intentionally mirrors SalesInvoiceItem VAT expressions for consistent
# Ash in-memory/ETS behavior; de-duplication requires cross-resource calculation redesign.
defmodule Firmowid.Ash.Invoicing.WizardDraft.Item do
  @moduledoc """
  Standalone ETS resource for line items within a WizardDraft.

  Represents a single invoice line item during the wizard flow. Lives in its own
  ETS table (`wizard_draft_items`) and is related to WizardDraft via `has_many` /
  `belongs_to`. Expression calculations for net/vat/gross mirror `SalesInvoiceItem`.

  Multitenancy by `organization_id` provides org-level isolation, same as all
  other resources. The ETS table is public (`private? false`) so it survives
  across processes and is managed by `Ash.DataLayer.Ets.TableManager`.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Invoicing.Validations.ValidateVatRate

  ets do
    private? false
    table :wizard_draft_items
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:index, :name, :quantity, :unit, :unit_price, :vat_rate, :wizard_draft_id]
      validate {ValidateVatRate, []}
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:index, :name, :quantity, :unit, :unit_price, :vat_rate]
      validate {ValidateVatRate, []}
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
    attribute :organization_id, :uuid_v7, public?: true
    attribute :wizard_draft_id, :uuid_v7, allow_nil?: false, public?: true

    attribute :index, :integer, public?: true
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :quantity, :decimal, public?: true, allow_nil?: false
    attribute :unit, :string, public?: true, default: "szt.", allow_nil?: false
    attribute :unit_price, :decimal, public?: true, allow_nil?: false
    attribute :vat_rate, :string, public?: true, allow_nil?: false
  end

  relationships do
    belongs_to :wizard_draft, Firmowid.Ash.Invoicing.WizardDraft do
      allow_nil? false
      attribute_writable? true
      define_attribute? false
      source_attribute :wizard_draft_id
    end
  end

  calculations do
    # Converts KSeF string VAT rate code to numeric decimal.
    # All non-numeric rates (zw, oo, np I, np II, 0 KR, 0 WDT, 0 EX) → 0.
    # NOTE: kept as inline expr — see SalesInvoiceItem for explanation.
    # This mapping is duplicated in SalesInvoiceItem — keep both in sync.
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
