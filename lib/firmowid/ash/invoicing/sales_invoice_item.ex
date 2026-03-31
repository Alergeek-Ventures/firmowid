defmodule Firmowid.Ash.Invoicing.SalesInvoiceItem do
  @moduledoc """
  Ash resource for sales invoice line items.

  Read-only in this slice — mutations remain in the legacy Ecto schema
  until Slice 7.

  ## Public functions

    * `get_net_value/1` — quantity × unit_price
    * `get_vat_value/1` — net_value × (vat_rate / 100)
    * `get_gross_value/1` — net_value + vat_value
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource
  alias Firmowid.Ksef.VatRate

  require Resource

  postgres do
    table "sales_invoice_items"
    repo Firmowid.Repo
    migrate? false
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
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

    belongs_to :sales_invoice, Firmowid.Ash.Invoicing.SalesInvoice do
      allow_nil? false
    end
  end

  # Public functions -----------------------------------------------------------

  @doc "Returns the net value (quantity × unit_price) for this line item."
  @spec get_net_value(struct()) :: Decimal.t()
  def get_net_value(%{unit_price: unit_price, quantity: quantity}) when not is_nil(unit_price) and not is_nil(quantity) do
    Decimal.mult(unit_price, quantity)
  end

  def get_net_value(_), do: Decimal.new(0)

  @doc "Returns the VAT amount for this line item."
  @spec get_vat_value(struct()) :: Decimal.t()
  def get_vat_value(%{unit_price: _, quantity: _, vat_rate: vat_rate} = item) when not is_nil(vat_rate) do
    numeric_rate = VatRate.to_numeric(vat_rate)
    Decimal.mult(get_net_value(item), Decimal.div(numeric_rate, 100))
  end

  def get_vat_value(_), do: Decimal.new(0)

  @doc "Returns the gross value (net + VAT) for this line item."
  @spec get_gross_value(struct()) :: Decimal.t()
  def get_gross_value(item) do
    Decimal.add(get_net_value(item), get_vat_value(item))
  end
end
