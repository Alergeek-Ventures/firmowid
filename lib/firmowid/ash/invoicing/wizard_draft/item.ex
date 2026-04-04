defmodule Firmowid.Ash.Invoicing.WizardDraft.Item do
  @moduledoc """
  Embedded resource for line items within a WizardDraft.

  Represents a single invoice line item during the wizard flow. Validates
  VAT rate inclusion. Stored as `{:array, Item}` attribute on WizardDraft.
  """
  use Ash.Resource, data_layer: :embedded

  alias Firmowid.Ash.Invoicing.Validations.ValidateVatRate

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate {ValidateVatRate, []}
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :index, :integer, public?: true
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :quantity, :decimal, public?: true, allow_nil?: false
    attribute :unit, :string, public?: true, default: "szt.", allow_nil?: false
    attribute :unit_price, :decimal, public?: true, allow_nil?: false
    attribute :vat_rate, :string, public?: true, allow_nil?: false
  end
end
